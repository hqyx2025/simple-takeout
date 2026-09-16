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
import com.example.takeout.model.Address;
import com.example.takeout.model.Goods;
import com.example.takeout.model.GoodsSpec;
import com.example.takeout.model.Order;
import com.example.takeout.model.Seckill;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
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
    private final HotDataCacheService cache = mock(HotDataCacheService.class);
    private final OrderService service = new OrderService(orderDao, storeDao, goodsDao, addressDao,
            couponDao, reviewDao, userDao, refundDao, new ObjectMapper(), mock(CartItemMapper.class),
            mock(RiderDao.class), specDao, seckillDao, cache,
            mock(com.example.takeout.service.mq.DomainEventPublisher.class),
            mock(org.springframework.beans.factory.ObjectProvider.class), mock(PaymentRecordDao.class));

    private static final long STORE_ID = 10L;
    private static final long GOODS_ID = 100L;
    private static final long ADDRESS_ID = 20L;
    private static final long USER_ID = 1L;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
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
                10, 3, 0, 13, "", 0, 0, LocalDateTime.now().format(FMT),
                status == 0 ? "" : LocalDateTime.now().format(FMT), "", "", "", expectTime, 0);
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
        verify(userDao, never()).deductBalance(anyLong(), anyDouble());
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
        when(userDao.deductBalance(USER_ID, 13.0)).thenReturn(true);

        service.payOrder(USER_ID, 13);

        // 条件扣款（余额不足会返回 false），不再用「读余额→减→整值写回」
        verify(userDao).deductBalance(eq(USER_ID), eq(13.0));
        verify(orderDao).markPaid(eq(13L), anyString());
    }

    @Test
    void rejectsPayingCancelledOrder() {
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 5, ITEMS, "")));

        BizException error = assertThrows(BizException.class, () -> service.payOrder(USER_ID, 13));

        assertEquals("订单已取消，无法支付", error.getMessage());
        verify(userDao, never()).deductBalance(anyLong(), anyDouble());
    }

    @Test
    void rejectsPayingOrderThatPassedItsPayDeadline() {
        // 待付款订单已过 15 分钟支付时限：支付必须直接拒绝，不再扣余额（超时定时任务会竞争取消）
        String expired = LocalDateTime.now().minusMinutes(16).format(FMT);
        Order overdue = new Order(13, "NO13", USER_ID, STORE_ID, "测试店", 0, ITEMS, ADDRESS_JSON,
                10, 3, 0, 13, "", 0, 0, expired, "", "", "", "", "", 0);
        when(orderDao.findById(13)).thenReturn(Optional.of(overdue));

        BizException error = assertThrows(BizException.class, () -> service.payOrder(USER_ID, 13));

        assertEquals("订单已超过支付时限，请重新下单", error.getMessage());
        verify(orderDao, never()).markPaid(anyLong(), anyString());
        verify(userDao, never()).deductBalance(anyLong(), anyDouble());
    }

    @Test
    void rejectsPayWhenConcurrentOrderTookTheBalance() {
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 0, ITEMS, "")));
        when(userDao.findById(USER_ID)).thenReturn(Optional.of(user(50)));
        when(orderDao.markPaid(eq(13L), anyString())).thenReturn(true);
        // 并发支付另一笔订单已抢先扣完余额：条件扣款失败必须整体回滚（订单状态一并回滚）
        when(userDao.deductBalance(USER_ID, 13.0)).thenReturn(false);

        BizException error = assertThrows(BizException.class, () -> service.payOrder(USER_ID, 13));

        assertEquals("余额不足，请先充值", error.getMessage());
        verify(userDao).deductBalance(USER_ID, 13.0);
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
        verify(userDao, never()).deductBalance(anyLong(), anyDouble());
        verify(userDao, never()).addBalance(anyLong(), anyDouble());
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
        when(orderDao.updateStatusFrom(eq(7L), eq(1), eq(5), eq("complete_time"), anyString())).thenReturn(true);
        when(userDao.findById(USER_ID)).thenReturn(Optional.of(user(37)));

        service.cancelOrder(USER_ID, 7);

        verify(orderDao).refundEscrow(7);
        verify(goodsDao).restoreStock(GOODS_ID, 1);
        // 退款用原子自增，避免与并发退款互相覆盖
        verify(userDao).addBalance(eq(USER_ID), eq(13.0));
        verify(orderDao).updateStatusFrom(eq(7L), eq(1), eq(5), eq("complete_time"), anyString());

        BizException error = assertThrows(BizException.class, () -> service.cancelOrder(USER_ID, 7));
        assertEquals("订单资金已处理，不能重复退款", error.getMessage());
    }

    @Test
    void cancelRollsBackWhenOrderWasAdvancedConcurrently() {
        Order order = storedOrder(7, 1, ITEMS, "");
        when(orderDao.findById(7)).thenReturn(Optional.of(order));
        when(orderDao.refundEscrow(7)).thenReturn(true);
        // 期间骑手/商户已把订单推进到已送达：条件状态更新失败 → 必须抛异常回滚退款
        when(orderDao.updateStatusFrom(eq(7L), eq(1), eq(5), eq("complete_time"), anyString())).thenReturn(false);

        BizException error = assertThrows(BizException.class, () -> service.cancelOrder(USER_ID, 7));

        assertEquals("订单状态已变化，请刷新后重试", error.getMessage());
        verify(goodsDao, never()).restoreStock(anyLong(), anyInt());
        verify(userDao, never()).addBalance(anyLong(), anyDouble());
    }

    @Test
    void merchantOrdersHideUnpaidOrders() {
        when(storeDao.listByOwner(USER_ID)).thenReturn(List.of(openStore(0, 3)));
        Order pending = storedOrder(21, 0, ITEMS, "");
        Order paid = storedOrder(22, 1, ITEMS, "");
        when(orderDao.listByStore(STORE_ID)).thenReturn(List.of(pending, paid));

        List<Order.OrderView> visible = service.merchantOrders(USER_ID);

        assertEquals(1, visible.size(), "待付款订单不应出现在商户待处理列表");
        assertEquals(22, visible.get(0).id());
    }

    @Test
    void rejectOrderWhenGoodsStockNotEnough() {
        stubCommon(10, 0, 3);
        when(goodsDao.deductStock(GOODS_ID, 1)).thenReturn(false);

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of()));

        assertTrue(error.getMessage().contains("库存不足"));
    }

    /** 下单防重 token：同一 idempotencyKey 第二次提交被拒；首次提交失败时释放占位允许重试。 */
    @Test
    void rejectsDuplicateIdempotencyKeyAndReleasesKeyOnFailure() {
        @SuppressWarnings("unchecked")
        org.springframework.beans.factory.ObjectProvider<StringRedisTemplate> provider =
                mock(org.springframework.beans.factory.ObjectProvider.class);
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        @SuppressWarnings("unchecked")
        org.springframework.data.redis.core.ValueOperations<String, String> ops =
                mock(org.springframework.data.redis.core.ValueOperations.class);
        when(provider.getIfAvailable()).thenReturn(redis);
        when(redis.opsForValue()).thenReturn(ops);
        OrderService svc = new OrderService(orderDao, storeDao, goodsDao, addressDao,
                couponDao, reviewDao, userDao, refundDao, new ObjectMapper(), mock(CartItemMapper.class),
                mock(RiderDao.class), specDao, seckillDao, cache,
                mock(com.example.takeout.service.mq.DomainEventPublisher.class), provider, mock(PaymentRecordDao.class));

        // 同一 token 第二次提交：SET NX 失败 → 拒绝，且不进任何业务校验
        when(ops.setIfAbsent(anyString(), anyString(), any(java.time.Duration.class))).thenReturn(false);
        BizException dup = assertThrows(BizException.class, () -> svc.createOrder(USER_ID, STORE_ID,
                List.of(item()), ADDRESS_ID, 0, "", List.of(), "", "key-1"));
        assertTrue(dup.getMessage().contains("请勿重复操作"), dup.getMessage());
        verify(orderDao, never()).insert(any(Order.class));

        // 首次提交但下单失败（空 items）：占位必须被释放，用户修正后可用同一 token 重试
        when(ops.setIfAbsent(anyString(), anyString(), any(java.time.Duration.class))).thenReturn(true);
        assertThrows(BizException.class, () -> svc.createOrder(USER_ID, STORE_ID,
                List.of(), ADDRESS_ID, 0, "", List.of(), "", "key-2"));
        verify(redis).delete("takeout:idempotent:order:" + USER_ID + ":key-2");
    }

    /** Redis 不可用时防重校验跳过，下单照常（加固不能反过来让下单不可用，与登录限流同口径）。 */
    @Test
    void idempotencyCheckSkippedWhenRedisUnavailable() {
        stubCommon(10, 0, 3);
        when(orderDao.insert(any(Order.class))).thenReturn(13L);
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 0, ITEMS, "")));

        // 类级 service 的 provider mock 未桩 getIfAvailable → 返回 null，等价 Redis 不可用
        Order.OrderView view = service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "",
                List.of(), "", "key-3");

        assertEquals(13, view.id());
    }

    // ============ 秒杀「一人一单」 ============

    private Seckill activeSeckill() {
        return new Seckill(400L, GOODS_ID, STORE_ID, 5.0, 100, 0,
                "2026-01-01 00:00:00", "2099-01-01 00:00:00", 1, "");
    }

    /** 秒杀下单：登记参与记录，且秒杀价生效（5 元 + 配送 3 元 = 8 元）。 */
    @Test
    void seckillOrderRegistersOnePerUserParticipation() {
        stubCommon(10, 0, 3);
        when(seckillDao.findActiveByGoods(anyLong(), anyString())).thenReturn(Optional.of(activeSeckill()));
        when(seckillDao.deductQuota(anyLong(), anyInt(), anyString())).thenReturn(true);
        when(seckillDao.joinOnce(anyLong(), anyLong(), anyLong(), anyString())).thenReturn(true);
        when(orderDao.insert(any(Order.class))).thenReturn(13L);
        when(orderDao.findById(13)).thenReturn(Optional.of(storedOrder(13, 0, ITEMS, "")));

        service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of());

        verify(orderDao).insert(org.mockito.ArgumentMatchers.argThat(o -> o.payAmount() == 8.0));
        verify(seckillDao).joinOnce(anyLong(), anyLong(), anyLong(), anyString());
    }

    /** 同一用户对同一场秒杀的第二笔订单被唯一键拦截，返回可读错误并回滚整单。 */
    @Test
    void rejectsSecondSeckillOrderForSameUser() {
        stubCommon(10, 0, 3);
        when(seckillDao.findActiveByGoods(anyLong(), anyString())).thenReturn(Optional.of(activeSeckill()));
        when(seckillDao.deductQuota(anyLong(), anyInt(), anyString())).thenReturn(true);
        when(seckillDao.joinOnce(anyLong(), anyLong(), anyLong(), anyString())).thenReturn(false);
        when(orderDao.insert(any(Order.class))).thenReturn(13L);

        BizException error = assertThrows(BizException.class, () ->
                service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of()));

        assertEquals("该秒杀商品每人限购一次，请勿重复下单", error.getMessage());
    }
}
