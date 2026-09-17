package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.AdminStatsDao;
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
import com.example.takeout.model.Address;
import com.example.takeout.model.CartItemEntity;
import com.example.takeout.model.Coupon;
import com.example.takeout.model.Goods;
import com.example.takeout.model.GoodsSpec;
import com.example.takeout.model.MarketingActivity;
import com.example.takeout.model.Order;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.model.Rider;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
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
 * 边界条件回归测试（对应用户可见的资金/状态机/金额口径缺陷）：
 * 退款只退已扣款订单、退款不再泄漏规格库存与秒杀名额、状态并发流转回滚、
 * 结算选择去重与跨店起送价、骑手收入同事务、输入长度上限。
 */
class OrderBoundaryTest {

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
    private final RiderDao riderDao = mock(RiderDao.class);
    private final CartItemMapper cartItemMapper = mock(CartItemMapper.class);
    private final HotDataCacheService cache = mock(HotDataCacheService.class);
    private final DomainEventPublisher eventPublisher = mock(DomainEventPublisher.class);

    private final OrderService service = new OrderService(orderDao, storeDao, goodsDao, addressDao,
            couponDao, reviewDao, userDao, refundDao, new ObjectMapper(), cartItemMapper,
            riderDao, specDao, seckillDao, cache, eventPublisher,
            mock(org.springframework.beans.factory.ObjectProvider.class), mock(PaymentRecordDao.class));

    private final AdminService adminService = new AdminService(storeDao, orderDao, userDao, goodsDao,
            refundDao, service, mock(AdminStatsDao.class), cache, eventPublisher, mock(PaymentRecordDao.class));

    private static final long STORE_ID = 10L;
    private static final long GOODS_ID = 100L;
    private static final long OTHER_STORE_GOODS_ID = 200L;
    private static final long ADDRESS_ID = 20L;
    private static final long USER_ID = 1L;
    private static final long OWNER_ID = 99L;
    private static final String ITEMS =
            "[{\"goodsId\":100,\"goodsName\":\"测试商品\",\"price\":10.0,\"quantity\":1,\"image\":\"\"}]";
    private static final String ADDRESS_JSON =
            "{\"addressId\":20,\"name\":\"张三\",\"phone\":\"13800138000\",\"detail\":\"测试地址\"}";

    // ============ 平台退款：资金边界 ============

    @Test
    void adminRefundRejectsOrdersWithoutCapturedFunds() {
        // 待付款：从未扣款，escrow 同样是 0，放行等于凭空给用户加钱
        when(orderDao.findById(31)).thenReturn(Optional.of(storedOrder(31, 0, 0)));
        BizException unpaid = assertThrows(BizException.class, () -> adminService.refundOrder(31));
        assertTrue(unpaid.getMessage().contains("当前状态不可直接退款"));
        verify(orderDao, never()).refundEscrow(anyLong());
        verify(userDao, never()).addBalance(anyLong(), anyDouble());

        // 待付款取消：同样未扣款，且如果放行还会重复回滚一次库存
        when(orderDao.findById(32)).thenReturn(Optional.of(storedOrder(32, 5, 0)));
        assertThrows(BizException.class, () -> adminService.refundOrder(32));
        verify(userDao, never()).addBalance(anyLong(), anyDouble());
        verify(goodsDao, never()).restoreStock(anyLong(), anyInt());
    }

    @Test
    void adminRefundRestoresSpecStockAndSeckillQuota() {
        String items = "[{\"goodsId\":100,\"goodsName\":\"测试商品\",\"price\":10.0,\"quantity\":2,"
                + "\"image\":\"\",\"specId\":300,\"specName\":\"大份\",\"seckillId\":400}]";
        when(orderDao.findById(33)).thenReturn(Optional.of(storedOrder(33, 1, 0, items)));
        when(orderDao.refundEscrow(33)).thenReturn(true);
        when(orderDao.updateStatusFrom(eq(33L), eq(1), eq(5), eq("complete_time"), anyString())).thenReturn(true);
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 3)));

        adminService.refundOrder(33);

        verify(goodsDao).restoreStock(GOODS_ID, 2);
        verify(specDao).restoreStock(300, 2);
        verify(seckillDao).restoreQuota(400, 2);
        verify(seckillDao).releaseOnce(USER_ID, 400);
        verify(userDao).addBalance(USER_ID, 13.0);
    }

    // ============ 状态机并发 ============

    @Test
    void merchantAcceptRollsBackWhenOrderAdvancedConcurrently() {
        when(orderDao.findById(7)).thenReturn(Optional.of(storedOrder(7, 1, 0)));
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 3)));
        // 期间用户已取消：条件状态更新失败必须整单回滚，而不是把已取消订单改回制作中
        when(orderDao.updateStatusFrom(eq(7L), eq(1), eq(2), eq("accept_time"), anyString())).thenReturn(false);

        BizException error = assertThrows(BizException.class, () -> service.merchantFlow(OWNER_ID, 7, "accept"));

        assertEquals("订单状态已变化，请刷新后重试", error.getMessage());
    }

    @Test
    void applyRefundDoesNotInsertWhenStatusChangedConcurrently() {
        when(orderDao.findById(8)).thenReturn(Optional.of(storedOrder(8, 4, 0)));
        when(refundDao.existsPending(8)).thenReturn(false);
        // 与「确认收货」并发：escrow 已被结算，状态流转失败 → 不得落下退款申请
        when(orderDao.markRefunding(8)).thenReturn(false);

        BizException error = assertThrows(BizException.class, () -> service.applyRefund(USER_ID, 8, "不想要了"));

        assertTrue(error.getMessage().contains("订单资金已处理或状态已变化"));
        verify(refundDao, never()).insert(anyLong(), anyLong(), anyLong(), anyString(), anyString(), anyDouble(), anyString());
    }

    @Test
    void riderDeliverRecordsIncomeInSameCall() {
        when(riderDao.findById(5)).thenReturn(Optional.of(
                new Rider(5, 3L, "骑手小张", "13300133000", 1, 0, 0.0, 1, "")));
        when(orderDao.riderDeliver(eq(9L), eq(5L), anyString())).thenReturn(true);
        when(orderDao.findById(9)).thenReturn(Optional.of(storedOrder(9, 3, 0)));
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 3)));

        service.riderDeliver(5, 9);

        verify(riderDao).addCompleted(5, 3.0);
    }

    // ============ 金额口径与结算边界 ============

    @Test
    void minOrderCheckIgnoresOtherStoreCartRows() {
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(50, 3)));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(
                new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(goods(GOODS_ID, STORE_ID, 10)));
        when(goodsDao.findById(OTHER_STORE_GOODS_ID))
                .thenReturn(Optional.of(goods(OTHER_STORE_GOODS_ID, 99, 100)));
        // 勾选里混入了别店的 100 份大额商品：本店实付只有 10 元，仍应被起送价拦住
        when(cartItemMapper.selectList(any())).thenReturn(List.of(
                cartRow(GOODS_ID, 0, 1), cartRow(OTHER_STORE_GOODS_ID, 0, 100)));

        BizException error = assertThrows(BizException.class, () -> service.createOrder(USER_ID, STORE_ID,
                List.of(item()), ADDRESS_ID, 0, "", List.of(GOODS_ID, OTHER_STORE_GOODS_ID)));

        assertTrue(error.getMessage().contains("未达到店铺起送价"));
        verify(orderDao, never()).insert(any(Order.class));
    }

    @Test
    void checkoutAcceptsSameGoodsSelectedWithTwoSpecs() {
        GoodsSpec small = new GoodsSpec(300, GOODS_ID, "小份", 10, 5, 0, 0, 1, "");
        GoodsSpec large = new GoodsSpec(301, GOODS_ID, "大份", 15, 5, 0, 0, 1, "");
        Goods multiSpec = goods(GOODS_ID, STORE_ID, 10).withSpecs(List.of(small, large));
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 3)));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(
                new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(multiSpec));
        when(goodsDao.deductStock(GOODS_ID, 2)).thenReturn(true);
        when(specDao.deductStock(300, 2)).thenReturn(true);
        when(cartItemMapper.selectList(any())).thenReturn(List.of(
                cartRow(GOODS_ID, 300, 1), cartRow(GOODS_ID, 301, 2)));
        when(orderDao.insert(any(Order.class))).thenReturn(13L);
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 0, 0)));

        // 结算上报以菜品为粒度，同一菜品的两个规格会重复上报同一个 goodsId，不能因此拒单
        service.createOrder(USER_ID, STORE_ID,
                List.of(new Order.OrderItem(GOODS_ID, "测试商品", 10, 2, "", 300, "小份", 0)),
                ADDRESS_ID, 0, "", List.of(GOODS_ID, GOODS_ID));

        verify(orderDao).insert(any(Order.class));
    }

    @Test
    void discountActivityReducesGoodsAmount() {
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 3)));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(
                new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(goods(GOODS_ID, STORE_ID, 10)));
        when(goodsDao.deductStock(GOODS_ID, 1)).thenReturn(true);
        when(storeDao.listActiveMarketingActivities(eq(STORE_ID), anyString())).thenReturn(List.of(
                new MarketingActivity(1, STORE_ID, "DISCOUNT", "全场8折", 0.8, 0, 0, 0,
                        "2026-01-01 00:00:00", "2099-12-31 23:59:59", 1, "2026-01-01 00:00:00")));
        when(orderDao.insert(any(Order.class))).thenReturn(13L);
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 0, 0)));

        service.createOrder(USER_ID, STORE_ID,
                List.of(new Order.OrderItem(GOODS_ID, "测试商品", 10, 1, "", 0, "", 0)),
                ADDRESS_ID, 0, "");

        org.mockito.ArgumentCaptor<Order> captor = org.mockito.ArgumentCaptor.forClass(Order.class);
        verify(orderDao).insert(captor.capture());
        assertEquals(8.0, captor.getValue().goodsAmount(), 0.001);
        assertEquals(11.0, captor.getValue().payAmount(), 0.001);
    }

    // ============ 输入长度边界 ============

    @Test
    void applyRefundRejectsOverlongReason() {
        when(orderDao.findById(8)).thenReturn(Optional.of(storedOrder(8, 4, 0)));
        when(refundDao.existsPending(8)).thenReturn(false);
        when(orderDao.markRefunding(8)).thenReturn(true);
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 3)));

        BizException error = assertThrows(BizException.class,
                () -> service.applyRefund(USER_ID, 8, "理".repeat(300)));

        assertEquals("退款原因最多 255 个字符", error.getMessage());
        verify(refundDao, never()).insert(anyLong(), anyLong(), anyLong(), anyString(), anyString(), anyDouble(), anyString());
    }

    @Test
    void applyRefundStoresStructuredReasonTypeAndRemark() {
        when(orderDao.findById(8)).thenReturn(Optional.of(storedOrder(8, 4, 0)));
        when(refundDao.existsPending(8)).thenReturn(false);
        when(orderDao.markRefunding(8)).thenReturn(true);
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 3)));
        when(refundDao.insert(anyLong(), anyLong(), anyLong(), anyString(), anyString(), anyDouble(), anyString()))
                .thenReturn(99L);
        when(refundDao.findById(99)).thenReturn(Optional.of(
                new RefundRecord(99, 8, USER_ID, OWNER_ID, "QUALITY_ISSUE", "汤洒了", 13.0, "PENDING", "", "", "")));

        RefundRecord rec = service.applyRefund(USER_ID, 8, "QUALITY_ISSUE", "汤洒了");

        assertEquals("QUALITY_ISSUE", rec.reasonType());
        verify(refundDao).insert(eq(8L), eq(USER_ID), eq(OWNER_ID), eq("QUALITY_ISSUE"), eq("汤洒了"), anyDouble(), anyString());
    }

    @Test
    void applyRefundRejectsUnknownReasonType() {
        BizException error = assertThrows(BizException.class,
                () -> service.applyRefund(USER_ID, 8, "HACK", ""));

        assertEquals("退款原因类型无效", error.getMessage());
        verify(refundDao, never()).insert(anyLong(), anyLong(), anyLong(), anyString(), anyString(), anyDouble(), anyString());
    }

    @Test
    void createOrderRejectsOverlongRemark() {
        stubMinimalOrderContext();

        BizException error = assertThrows(BizException.class, () -> service.createOrder(USER_ID, STORE_ID,
                List.of(item()), ADDRESS_ID, 0, "备".repeat(300), List.of()));

        assertEquals("订单备注最多 255 个字符", error.getMessage());
        verify(orderDao, never()).insert(any(Order.class));
    }

    @Test
    void createOrderRejectsCouponThatCoversTheWholeOrder() {
        stubMinimalOrderContext();
        // 门槛 0 元、面额 20 元：券后应付 0 元（货款 10 + 配送费 3 - 20 < 0 已由负值校验拦住，
        // 这里取面额恰好等于应付的临界值）
        when(couponDao.listByUser(USER_ID)).thenReturn(List.of(
                new Coupon(66, USER_ID, 0, "测试券", 0, 13, 0, "2030-01-01 00:00:00", "", "2026-08-16 10:00:00")));

        BizException error = assertThrows(BizException.class, () -> service.createOrder(USER_ID, STORE_ID,
                List.of(item()), ADDRESS_ID, 66, "", List.of()));

        assertEquals("优惠券抵扣后应付金额为 0，请更换优惠券", error.getMessage());
        verify(couponDao, never()).markUsed(anyLong());
        verify(orderDao, never()).insert(any(Order.class));
    }

    // ============ 夹具 ============

    private Store openStore(double minOrder, double deliveryFee) {
        return new Store(STORE_ID, "测试店", "", 4.5, 0, deliveryFee, minOrder, "30分钟", "1km", "[]", "",
                1, "[1]", OWNER_ID, 1, 0, "");
    }

    private Goods goods(long id, long storeId, double price) {
        return new Goods(id, storeId, "测试商品", "", price, price, "", 1, 0, 999, 0, 0, 4.5, "", false, 1, "");
    }

    private Order.OrderItem item() {
        return new Order.OrderItem(GOODS_ID, "测试商品", 10, 1, "");
    }

    private Order storedOrder(long id, int status, int escrowStatus) {
        return storedOrder(id, status, escrowStatus, ITEMS);
    }

    private Order storedOrder(long id, int status, int escrowStatus, String items) {
        return new Order(id, "NO" + id, USER_ID, STORE_ID, "测试店", status, items, ADDRESS_JSON,
                10, 3, 0, 13, "", 0, escrowStatus, "2026-08-16 10:00:00",
                status == 0 ? "" : "2026-08-16 10:00:00", "", "", "", "", 0);
    }

    private CartItemEntity cartRow(long goodsId, long specId, int quantity) {
        CartItemEntity row = new CartItemEntity();
        row.setUserId(USER_ID);
        row.setGoodsId(goodsId);
        row.setSpecId(specId);
        row.setQuantity(quantity);
        return row;
    }

    private void stubMinimalOrderContext() {
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(0, 3)));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(
                new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(goods(GOODS_ID, STORE_ID, 10)));
        when(userDao.findById(USER_ID)).thenReturn(Optional.of(
                new User(USER_ID, "测试用户", "", "13800138000", "", 0, 50, "2026-08-16 10:00:00")));
        when(goodsDao.deductStock(GOODS_ID, 1)).thenReturn(true);
    }
}