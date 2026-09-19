package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.CouponDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.ReviewDao;
import com.example.takeout.dao.RiderDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.Order;
import com.example.takeout.model.Rider;
import com.example.takeout.model.Store;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 骑手真正参与配送的闭环测试。
 *
 * <p>这条链最容易断的地方不是骑手接口本身，而是**商户出餐必须走 ready**：出餐若走 deliver（2→3），
 * 订单就再也不会出现在「待取餐池」里（池子按 status=2 + ready_time 非空筛选），骑手端于是永远空列表、
 * 抢单永远失败。本测试把「出餐 → 进池 → 抢单 → 取餐 → 送达 → 计收入」整条链钉住。
 */
class OrderServiceRiderFlowTest {

    private static final long STORE_ID = 10L;
    /** 距骑手约 100 公里的门店：超出默认 25 公里骑手半径，配单时应被过滤。 */
    private static final long FAR_STORE_ID = 11L;
    private static final long ORDER_ID = 500L;
    private static final long OWNER_ID = 99L;
    private static final long RIDER_ID = 77L;
    private static final String ADDRESS_JSON =
            "{\"addressId\":20,\"name\":\"张三\",\"phone\":\"13800138000\",\"detail\":\"测试地址\"}";
    private static final String ITEMS =
            "[{\"goodsId\":100,\"goodsName\":\"测试商品\",\"price\":10.0,\"quantity\":1,\"image\":\"\"}]";

    private final OrderDao orderDao = mock(OrderDao.class);
    private final StoreDao storeDao = mock(StoreDao.class);
    private final RiderDao riderDao = mock(RiderDao.class);
    private final OrderService service = new OrderService(orderDao, storeDao, mock(GoodsDao.class),
            mock(AddressDao.class), mock(CouponDao.class), mock(ReviewDao.class), mock(UserDao.class),
            mock(RefundDao.class), new ObjectMapper(), mock(CartItemMapper.class), riderDao,
            mock(GoodsSpecDao.class), mock(SeckillDao.class), mock(HotDataCacheService.class),
            mock(com.example.takeout.service.mq.DomainEventPublisher.class),
            mock(org.springframework.beans.factory.ObjectProvider.class), mock(PaymentRecordDao.class));

    /** 服务层独立校验骑手未被停用：走 riderGrab/riderPickup/riderDeliver 的用例必须先桩一个启用中的骑手档案。 */
    private void stubActiveRider() {
        // 骑手必须带接单位置与半径，否则配单判定（门店是否在自己半径内）会直接不派单
        when(riderDao.findById(RIDER_ID)).thenReturn(Optional.of(
                new Rider(RIDER_ID, 5L, "骑手小张", "13300133000", 1, 0, 0.0, 1, 25000,
                        22.8177, 108.3665, "南宁市青秀区", "")));
    }

    /** 库中订单（25 个组件：id..couponId 为模型字段，rider_id / ready_time 由 DAO 单独读写）。 */
    private Order storedOrder(int status) {
        return new Order(ORDER_ID, "NO500", 1L, STORE_ID, "测试店", status, ITEMS, ADDRESS_JSON,
                10, 5, 0, 15, "", 0, 0, "2026-09-15 10:00:00",
                "2026-09-15 10:01:00", "", "", "", "", 0);
    }

    private void stubStore() {
        // 门店与骑手相距约 60 米，落在默认 25 公里骑手半径内
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(
                new Store(STORE_ID, "测试店", "", 4.5, 0, 5, 10, "30分钟", "1km", "[]", "",
                        "南宁市青秀区", 22.8180, 108.3670, 1, "[1]", OWNER_ID, 1, 0, "", 0)));
    }

    /** 列表里带一个"远店"单：配单必须只在骑手半径内的门店。 */
    private Order farStoredOrder(int status) {
        return new Order(ORDER_ID + 1, "NO501", 1L, FAR_STORE_ID, "远店", status, ITEMS, ADDRESS_JSON,
                10, 5, 0, 15, "", 0, 0, "2026-09-15 10:00:00",
                "2026-09-15 10:01:00", "", "", "", "", 0);
    }

    private void stubFarStore() {
        // 纬度 +0.9 度 ≈ 100 公里，远超骑手半径
        when(storeDao.findById(FAR_STORE_ID)).thenReturn(Optional.of(
                new Store(FAR_STORE_ID, "远店", "", 4.5, 0, 5, 10, "30分钟", "1km", "[]", "",
                        "南宁市", 23.7177, 108.3665, 1, "[1]", OWNER_ID, 1, 0, "", 0)));
    }

    /**
     * 平台配单：只在「商家半径 ∩ 骑手半径」内。
     * 商家半径一侧在下单时已按收货地址校验（超距直接拒绝下单），池子侧只需再按骑手半径过滤。
     */
    @Test
    void poolOnlyContainsOrdersWithinRiderRadius() {
        stubActiveRider();
        stubStore();
        stubFarStore();
        when(orderDao.listRiderPool()).thenReturn(List.of(storedOrder(2), farStoredOrder(2)));

        List<Order.OrderView> pool = service.riderPool(RIDER_ID);

        assertEquals(1, pool.size());
        assertEquals(ORDER_ID, pool.get(0).id());
    }

    /** 骑手没设置接单位置时无法判定半径 → 不派任何单（前端提示先去设置）。 */
    @Test
    void poolIsEmptyWhenRiderHasNoLocation() {
        when(riderDao.findById(RIDER_ID)).thenReturn(Optional.of(
                new Rider(RIDER_ID, 5L, "骑手小张", "13300133000", 1, 0, 0.0, 1, 25000,
                        null, null, "", "")));
        when(orderDao.listRiderPool()).thenReturn(List.of(storedOrder(2)));

        assertEquals(0, service.riderPool(RIDER_ID).size());
    }

    /** 抢单也不能绕过半径：直接拿订单 id 调接口同样要被拒。 */
    @Test
    void grabIsRejectedForOrderOutsideRiderRadius() {
        stubActiveRider();
        stubFarStore();
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(farStoredOrder(2)));

        BizException error = assertThrows(BizException.class, () -> service.riderGrab(RIDER_ID, ORDER_ID));

        assertTrue(error.getMessage().contains("不在您的配送范围内"), error.getMessage());
    }

    @Test
    void merchantReadyPutsOrderIntoRiderPoolWithoutChangingStatus() {
        stubStore();
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(2)));
        when(orderDao.markReady(eq(ORDER_ID), anyString())).thenReturn(true);

        Order.OrderView view = service.merchantFlow(OWNER_ID, ORDER_ID, "ready");

        // 出餐只写 ready_time，数字状态仍是 2（制作中）——池子按 status=2 + ready_time 筛选
        assertEquals(2, view.status());
        verify(orderDao).markReady(eq(ORDER_ID), anyString());
        // 绝不能把订单推到配送中：那会让它永久绕过骑手
        verify(orderDao, never()).merchantDeliver(anyLong(), anyString());
    }

    @Test
    void repeatingReadyIsRejectedWithReadableReason() {
        stubStore();
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(2)));
        when(orderDao.markReady(eq(ORDER_ID), anyString())).thenReturn(false);

        BizException error = assertThrows(BizException.class,
                () -> service.merchantFlow(OWNER_ID, ORDER_ID, "ready"));
        assertTrue(error.getMessage().contains("已出餐"), error.getMessage());
    }

    @Test
    void deliveredOrderWithReadyTimeShowsUpInPool() {
        stubActiveRider();
        stubStore();
        when(orderDao.listRiderPool()).thenReturn(List.of(storedOrder(2)));

        // 池子按骑手半径过滤：门店必须在骑手接单位置的配送半径内
        List<Order.OrderView> pool = service.riderPool(RIDER_ID);

        assertEquals(1, pool.size());
        assertEquals(ORDER_ID, pool.get(0).id());
    }

    @Test
    void riderGrabBindsRiderAndIsRejectedWhenSomeoneElseTookIt() {
        stubActiveRider();
        stubStore();
        when(orderDao.tryAssignRider(ORDER_ID, RIDER_ID)).thenReturn(true);
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(2)));

        assertEquals(ORDER_ID, service.riderGrab(RIDER_ID, ORDER_ID).id());

        // 条件更新返回 false = 已被别的骑手抢走 / 还没出餐，必须报错而不是静默成功
        when(orderDao.tryAssignRider(ORDER_ID, RIDER_ID)).thenReturn(false);
        BizException error = assertThrows(BizException.class, () -> service.riderGrab(RIDER_ID, ORDER_ID));
        assertTrue(error.getMessage().contains("手慢了"), error.getMessage());
    }

    @Test
    void fullChainFromReadyToDeliveredAccumulatesRiderIncome() {
        stubActiveRider();
        stubStore();
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(2)));
        when(orderDao.markReady(eq(ORDER_ID), anyString())).thenReturn(true);
        service.merchantFlow(OWNER_ID, ORDER_ID, "ready");

        // 抢单 → 取餐 → 送达
        when(orderDao.tryAssignRider(ORDER_ID, RIDER_ID)).thenReturn(true);
        service.riderGrab(RIDER_ID, ORDER_ID);

        when(orderDao.riderPickup(eq(ORDER_ID), eq(RIDER_ID), anyString())).thenReturn(true);
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(3)));
        assertEquals(3, service.riderPickup(RIDER_ID, ORDER_ID).status());

        when(orderDao.riderDeliver(eq(ORDER_ID), eq(RIDER_ID), anyString())).thenReturn(true);
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(4)));
        assertEquals(4, service.riderDeliver(RIDER_ID, ORDER_ID).status());

        // 单量/收入在同一事务内按订单配送费累加
        verify(riderDao).addCompleted(eq(RIDER_ID), anyDouble());
    }

    @Test
    void riderActionsFailWhenOrderIsNotYours() {
        stubActiveRider();
        when(orderDao.riderPickup(eq(ORDER_ID), eq(RIDER_ID), anyString())).thenReturn(false);
        BizException pickup = assertThrows(BizException.class, () -> service.riderPickup(RIDER_ID, ORDER_ID));
        assertTrue(pickup.getMessage().contains("无法取餐"), pickup.getMessage());

        when(orderDao.riderDeliver(eq(ORDER_ID), eq(RIDER_ID), anyString())).thenReturn(false);
        BizException deliver = assertThrows(BizException.class, () -> service.riderDeliver(RIDER_ID, ORDER_ID));
        assertTrue(deliver.getMessage().contains("无法送达"), deliver.getMessage());
        // 送达失败绝不能给骑手记一笔收入
        verify(riderDao, never()).addCompleted(anyLong(), anyDouble());
    }

    @Test
    void disabledRiderCannotGrabPickupOrDeliver() {
        // 平台停用的骑手（status=0）：控制器有在线/停用校验，服务层必须独立兜底，
        // 防止绕过控制器的调用路径（内部调用/新增接口）让停用骑手继续接单配送
        when(riderDao.findById(RIDER_ID)).thenReturn(Optional.of(
                new Rider(RIDER_ID, 5L, "骑手小张", "13300133000", 1, 0, 0.0, 0, 25000,
                        22.8177, 108.3665, "南宁市青秀区", "")));

        BizException grab = assertThrows(BizException.class, () -> service.riderGrab(RIDER_ID, ORDER_ID));
        assertEquals(403, grab.getCode());
        verify(orderDao, never()).tryAssignRider(anyLong(), anyLong());

        BizException pickup = assertThrows(BizException.class, () -> service.riderPickup(RIDER_ID, ORDER_ID));
        assertEquals(403, pickup.getCode());

        BizException deliver = assertThrows(BizException.class, () -> service.riderDeliver(RIDER_ID, ORDER_ID));
        assertEquals(403, deliver.getCode());
        // 停用骑手绝不能记一笔收入
        verify(riderDao, never()).addCompleted(anyLong(), anyDouble());
    }

    @Test
    void merchantCannotAdvanceOrderAlreadyTakenByRider() {
        stubStore();
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(2)));
        when(orderDao.findRiderId(ORDER_ID)).thenReturn(RIDER_ID);

        // 已由骑手接单：商户侧 deliver 要被拦下，并给出可读原因
        BizException error = assertThrows(BizException.class,
                () -> service.merchantFlow(OWNER_ID, ORDER_ID, "deliver"));
        assertTrue(error.getMessage().contains("骑手"), error.getMessage());
        verify(orderDao, never()).merchantDeliver(anyLong(), anyString());
    }

    @Test
    void merchantOrderListExposesRiderSoMerchantKnowsWhoTookIt() {
        stubStore();
        when(storeDao.listByOwner(OWNER_ID)).thenReturn(List.of(
                new Store(STORE_ID, "测试店", "", 4.5, 0, 5, 10, "30分钟", "1km", "[]", "",
                        1, "[1]", OWNER_ID, 1, 0, "")));
        when(orderDao.listByStore(STORE_ID)).thenReturn(List.of(storedOrder(3)));
        when(orderDao.findRiderId(ORDER_ID)).thenReturn(RIDER_ID);
        when(riderDao.findById(RIDER_ID)).thenReturn(Optional.of(
                new Rider(RIDER_ID, 5L, "骑手小张", "13300133000", 1, 0, 0.0, 1, 25000,
                        22.8177, 108.3665, "南宁市青秀区", "")));

        List<Order.OrderView> orders = service.merchantOrders(OWNER_ID);

        assertEquals(1, orders.size());
        // 商户列表要能看出订单已被骑手接走（前端据此隐藏商户侧流转按钮）
        assertEquals("骑手小张", orders.get(0).riderName());
    }
}
