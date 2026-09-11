package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.CouponDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.ReviewDao;
import com.example.takeout.dao.RiderDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.Address;
import com.example.takeout.model.Goods;
import com.example.takeout.model.GoodsSpec;
import com.example.takeout.model.Order;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 订单业务闭环测试：下单前置校验、待付款占库存、支付扣款、取消退款幂等、超时自动取消、多规格下单。
 */
class OrderServiceFlowTest {

    private final OrderDao orderDao = mock(OrderDao.class);
    private final StoreDao storeDao = mock(StoreDao.class);
    private final GoodsDao goodsDao = mock(GoodsDao.class);
    private final AddressDao addressDao = mock(AddressDao.class);
    private final CouponDao couponDao = mock(CouponDao.class);
    private final ReviewDao reviewDao = mock(ReviewDao.class);
    private final UserDao userDao = mock(UserDao.class);
    private final RefundDao refundDao = mock(RefundDao.class);
    private final GoodsSpecDao specDao = mock(GoodsSpecDao.class);
    private final SeckillDao seckillDao = mock(SeckillDao.class);
    private final OrderService service = new OrderService(orderDao, storeDao, goodsDao, addressDao,
            couponDao, reviewDao, userDao, refundDao, new ObjectMapper(), mock(CartItemMapper.class),
            mock(RiderDao.class), specDao, seckillDao);

    private static final long STORE_ID = 10L;
    private static final long GOODS_ID = 100L;
    private static final long ADDRESS_ID = 20L;
    private static final long USER_ID = 1L;
    private static final String ITEMS =
            "[{\"goodsId\":100,\"goodsName\":\"测试商品\",\"price\":10.0,\"quantity\":1,\"image\":\"\"}]";
    private static final String ADDRESS_JSON =
            "{\"addressId\":20,\"name\":\"张三\",\"phone\":\"13800138000\",\"detail\":\"测试地址\"}";

    private Store openStore(double minOrder, double deliveryFee) {
        return new Store(STORE_ID, "测试店", "", 4.5, 0, deliveryFee, minOrder, "30分钟", "1km", "[]", "",
                1, "[1]", 99, 1, 0, "");
    }

    private Goods shelfGoods(double price, long storeId) {
        return new Goods(GOODS_ID, storeId, "测试商品", "", price, price, "", 1, 0, 999, 0, 0, 4.5, "", false, 1, "");
    }

    private User user(double balance) {
        return new User(USER_ID, "测试用户", "", "13800138000", "", 0, balance, "2026-08-16 10:00:00");
    }

    private Order.OrderItem item() {
        return new Order.OrderItem(GOODS_ID, "测试商品", 10, 1, "");
    }

    /** 库中已落库的订单（状态与时间按用例传入）。 */
    private Order storedOrder(long id, int status, String couponIdFreeItems, String expectTime) {
        return new Order(id, "NO" + id, USER_ID, STORE_ID, "测试店", status, couponIdFreeItems, ADDRESS_JSON,
                10, 3, 0, 13, "", 0, 0, "2026-08-16 10:00:00",
                status == 0 ? "" : "2026-08-16 10:00:00", "", "", "", expectTime, 0);
    }

    private void stubCommon(double price, double minOrder, double deliveryFee) {
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(minOrder, deliveryFee)));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(shelfGoods(price, STORE_ID)));
        when(userDao.findById(USER_ID)).thenReturn(Optional.of(user(50)));
        when(goodsDao.deductStock(GOODS_ID, 1)).thenReturn(true);
    }

    @Test
    void createsPendingOrderReservingStockWithoutChargingBalance() {
        stubCommon(10, 0, 3);
        when(orderDao.insert(any(Order.class))).thenReturn(13L);
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 0, ITEMS, "")));

        Order.OrderView view = service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of());

        assertEquals(0, view.status(), "下单后进入待付款");
        assertEquals("", view.payTime(), "待付款订单支付时间为空");
        assertEquals(13.0, view.payAmount(), 0.001);
        assertFalse(view.payDeadline().isEmpty(), "待付款订单返回支付截止时间");
        verify(userDao, never()).updateBalance(anyLong(), anyDouble());
        verify(goodsDao).deductStock(GOODS_ID, 1);
        verify(storeDao).updateMonthlySales(STORE_ID, 1);
        verify(orderDao).insert(org.mockito.ArgumentMatchers.argThat(o ->
                o.status() == 0 && o.payTime().isEmpty() && o.payAmount() == 13.0));
    }

    @Test
    void paysPendingOrderDeductingBalance() {
        Order pending = storedOrder(13, 0, ITEMS, "");
        when(orderDao.findById(13)).thenReturn(Optional.of(pending));
        when(userDao.findById(USER_ID)).thenReturn(Optional.of(user(50)));
        when(orderDao.markPaid(eq(13L), anyString())).thenReturn(true);

        service.payOrder(USER_ID, 13);

        verify(userDao).updateBalance(eq(USER_ID), eq(37.0));
        verify(orderDao).markPaid(eq(13L), anyString());
    }

    @Test
    void rejectsPayingCancelledOrder() {
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 5, ITEMS, "")));

        BizException error = assertThrows(BizException.class, () -> service.payOrder(USER_ID, 13));

        assertEquals("订单已取消，无法支付", error.getMessage());
        verify(userDao, never()).updateBalance(anyLong(), anyDouble());
    }

    @Test
    void rejectsPayingWhenBalanceInsufficient() {
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 0, ITEMS, "")));
        when(userDao.findById(USER_ID)).thenReturn(Optional.of(user(5)));

        BizException error = assertThrows(BizException.class, () -> service.payOrder(USER_ID, 13));

        assertEquals("余额不足，请先充值", error.getMessage());
        verify(orderDao, never()).markPaid(anyLong(), anyString());
    }

    @Test
    void cancellingPendingOrderReleasesStockWithoutRefund() {
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 0, ITEMS, "")));
        when(orderDao.cancelPending(eq(13L), anyString())).thenReturn(true);

        service.cancelOrder(USER_ID, 13);

        verify(orderDao, never()).refundEscrow(anyLong());
        verify(userDao, never()).updateBalance(anyLong(), anyDouble());
        verify(goodsDao).restoreStock(GOODS_ID, 1);
        verify(orderDao).cancelPending(eq(13L), anyString());
    }

    @Test
    void cancellingPendingOrderReleasesCoupon() {
        Order pending = new Order(14, "NO14", USER_ID, STORE_ID, "测试店", 0, ITEMS, ADDRESS_JSON,
                10, 3, 3, 10, "", 0, 0, "2026-08-16 10:00:00", "", "", "", "", "", 66);
        when(orderDao.findById(14)).thenReturn(Optional.of(pending));
        when(orderDao.cancelPending(eq(14L), anyString())).thenReturn(true);

        service.cancelOrder(USER_ID, 14);

        verify(couponDao).release(eq(66L), anyString());
    }

    @Test
    void timeoutJobCancelsExpiredPendingOrders() {
        when(orderDao.listExpiredPending(anyString())).thenReturn(List.of(storedOrder(15, 0, ITEMS, "")));
        when(orderDao.cancelPending(eq(15L), anyString())).thenReturn(true);

        int cancelled = service.cancelExpiredPendingOrders();

        assertEquals(1, cancelled);
        verify(goodsDao).restoreStock(GOODS_ID, 1);
    }

    @Test
    void timeoutJobSkipsOrderPaidInTheMeantime() {
        when(orderDao.listExpiredPending(anyString())).thenReturn(List.of(storedOrder(16, 0, ITEMS, "")));
        when(orderDao.cancelPending(eq(16L), anyString())).thenReturn(false);

        int cancelled = service.cancelExpiredPendingOrders();

        assertEquals(0, cancelled);
        verify(goodsDao, never()).restoreStock(anyLong(), anyInt());
    }

    @Test
    void multiSpecOrderDeductsSpecStockAndSnapshotsSpecName() {
        GoodsSpec spec = new GoodsSpec(300, GOODS_ID, "大份", 12, 5, 0, 0, 1, "");
        Goods multi = new Goods(GOODS_ID, STORE_ID, "测试商品", "", 10, 10, "", 1, 0, 5, 0, 0, 4.5, "", false, 1, "")
                .withSpecs(List.of(spec));
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 0)));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(multi));
        when(goodsDao.deductStock(GOODS_ID, 2)).thenReturn(true);
        when(specDao.deductStock(300, 2)).thenReturn(true);
        when(orderDao.insert(any(Order.class))).thenReturn(17L);
        when(orderDao.findById(17)).thenReturn(Optional.of(storedOrder(17, 0, ITEMS, "")));

        service.createOrder(USER_ID, STORE_ID,
                List.of(new Order.OrderItem(GOODS_ID, "测试商品", 0, 2, "", 300, "", 0)), ADDRESS_ID, 0, "", List.of());

        verify(specDao).deductStock(300, 2);
        verify(goodsDao).deductStock(GOODS_ID, 2);
        verify(orderDao).insert(org.mockito.ArgumentMatchers.argThat(o ->
                o.goodsAmount() == 24.0 && o.items().contains("\"specName\":\"大份\"")));
    }

    @Test
    void rejectsMultiSpecGoodsWithoutSpecSelection() {
        GoodsSpec spec = new GoodsSpec(300, GOODS_ID, "大份", 12, 5, 0, 0, 1, "");
        Goods multi = new Goods(GOODS_ID, STORE_ID, "测试商品", "", 10, 10, "", 1, 0, 5, 0, 0, 4.5, "", false, 1, "")
                .withSpecs(List.of(spec));
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 0)));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(multi));

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of()));

        assertEquals("「测试商品」请先选择规格", error.getMessage());
        verify(orderDao, never()).insert(any(Order.class));
    }

    @Test
    void savesFutureExpectTimeForScheduledDelivery() {
        stubCommon(10, 0, 3);
        String future = java.time.LocalDateTime.now().plusHours(2)
                .format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        when(orderDao.insert(any(Order.class))).thenReturn(13L);
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 0, ITEMS, future)));

        Order.OrderView view = service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "",
                List.of(), future);

        assertEquals(future, view.expectTime());
        verify(orderDao).insert(org.mockito.ArgumentMatchers.argThat(o -> future.equals(o.expectTime())));
    }

    @Test
    void rejectsPastExpectTime() {
        stubCommon(10, 0, 3);

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "",
                        List.of(), "2020-01-01 10:00:00"));

        assertEquals("预约送达时间必须晚于当前时间", error.getMessage());
    }

    @Test
    void rejectsMalformedExpectTime() {
        stubCommon(10, 0, 3);

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "",
                        List.of(), "明天下午3点"));

        assertEquals("预约送达时间格式不正确", error.getMessage());
    }

    @Test
    void rejectsOrderBelowMinimumOrder() {
        stubCommon(10, 20, 3);

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of()));

        assertEquals("未达到店铺起送价（满20元起送）", error.getMessage());
        verify(orderDao, never()).insert(any(Order.class));
    }

    @Test
    void rejectsOrderWhenStoreClosed() {
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(
                new Store(STORE_ID, "测试店", "", 4.5, 0, 3, 0, "30分钟", "1km", "[]", "", 1, "[1]", 99, 0, 0, "")));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(shelfGoods(10, STORE_ID)));

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of()));

        assertEquals("店铺当前未营业", error.getMessage());
        verify(orderDao, never()).insert(any(Order.class));
    }

    @Test
    void cancelRefundsBalanceAndRestoresStockOnce() {
        Order order = storedOrder(7, 1, ITEMS, "");
        when(orderDao.findById(7)).thenReturn(Optional.of(order));
        when(orderDao.refundEscrow(7)).thenReturn(true, false);
        when(userDao.findById(USER_ID)).thenReturn(Optional.of(user(37)));

        service.cancelOrder(USER_ID, 7);

        verify(orderDao).refundEscrow(7);
        verify(goodsDao).restoreStock(GOODS_ID, 1);
        verify(userDao).updateBalance(eq(USER_ID), eq(50.0));
        verify(orderDao).updateStatus(eq(7L), eq(5), eq("complete_time"), anyString());

        BizException error = assertThrows(BizException.class, () -> service.cancelOrder(USER_ID, 7));
        assertEquals("订单资金已处理，不能重复退款", error.getMessage());
    }

    @Test
    void rejectOrderWhenGoodsStockNotEnough() {
        stubCommon(10, 0, 3);
        when(goodsDao.deductStock(GOODS_ID, 1)).thenReturn(false);

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of()));

        assertTrue(error.getMessage().contains("库存不足"));
    }
}
