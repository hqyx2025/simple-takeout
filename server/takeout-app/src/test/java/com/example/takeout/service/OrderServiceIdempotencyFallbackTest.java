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
import com.example.takeout.model.Order;
import com.example.takeout.model.Store;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.data.redis.RedisConnectionFailureException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Redis 故障不阻断下单，数据库唯一键继续保证请求防重。
 */
class OrderServiceIdempotencyFallbackTest {

    @Test
    void databaseReturnsCompletedReplayBeforeReservingStockEvenWithoutRedis() {
        org.mockito.Mockito.doThrow(new org.springframework.dao.DuplicateKeyException("PRIMARY"))
                .when(orderDao).reserveCreateRequest(USER_ID, "committed-request");
        when(orderDao.findCompletedCreateRequest(USER_ID, "committed-request")).thenReturn(Optional.of(13L));
        when(orderDao.findById(13L)).thenReturn(Optional.of(storedOrder(13L)));

        Order.OrderView replay = serviceWithRedis(null).createOrder(
                USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of(), "",
                " committed-request ", List.of(), "");

        assertEquals(13L, replay.id());
        org.mockito.Mockito.verifyNoInteractions(goodsDao, couponDao, storeDao);
        org.mockito.Mockito.verify(orderDao, org.mockito.Mockito.never()).insert(any(Order.class));
    }

    @Test
    void databaseDuplicateWithoutCompletedOrderReportsInProgress() {
        org.mockito.Mockito.doThrow(new org.springframework.dao.DuplicateKeyException("PRIMARY"))
                .when(orderDao).reserveCreateRequest(USER_ID, "in-progress");
        when(orderDao.findCompletedCreateRequest(USER_ID, "in-progress")).thenReturn(Optional.empty());

        BizException error = assertThrows(BizException.class, () -> serviceWithRedis(null).createOrder(
                USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of(), "",
                "in-progress", List.of(), ""));

        assertEquals("订单正在提交中，请稍后重试", error.getMessage());
        org.mockito.Mockito.verifyNoInteractions(goodsDao, couponDao, storeDao);
    }

    @Test
    void databaseLegacyPlaceholderDirectsUserToOrderList() {
        org.mockito.Mockito.doThrow(new org.springframework.dao.DuplicateKeyException("PRIMARY"))
                .when(orderDao).reserveCreateRequest(USER_ID, "legacy-request");
        when(orderDao.findCompletedCreateRequest(USER_ID, "legacy-request")).thenReturn(Optional.empty());
        when(orderDao.isHistoricalCreateRequest(org.mockito.ArgumentMatchers.eq(USER_ID),
                org.mockito.ArgumentMatchers.eq("legacy-request"), anyString())).thenReturn(true);

        BizException error = assertThrows(BizException.class, () -> serviceWithRedis(null).createOrder(
                USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of(), "",
                "legacy-request", List.of(), ""));

        assertEquals("订单可能已提交，请在订单列表核对，不要重复下单", error.getMessage());
        org.mockito.Mockito.verifyNoInteractions(goodsDao, couponDao, storeDao);
    }

    @Test
    void rejectsOversizedRequestKeyBeforeAnyStorageAccess() {
        assertThrows(BizException.class, () -> serviceWithRedis(null).createOrder(
                USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of(), "",
                "x".repeat(129), List.of(), ""));
        org.mockito.Mockito.verifyNoInteractions(orderDao, goodsDao, couponDao);
    }

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

    private static final long STORE_ID = 10L;
    private static final long GOODS_ID = 100L;
    private static final long ADDRESS_ID = 20L;
    private static final long USER_ID = 1L;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @SuppressWarnings("unchecked")
    private OrderService serviceWithRedis(StringRedisTemplate redis) {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);
        return new OrderService(orderDao, storeDao, goodsDao, addressDao,
                couponDao, reviewDao, userDao, refundDao, new ObjectMapper(), mock(CartItemMapper.class),
                mock(RiderDao.class), specDao, seckillDao, cache,
                mock(DomainEventPublisher.class), provider, mock(PaymentRecordDao.class));
    }

    private void stubCommon() {
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(new Store(STORE_ID, "测试店", "", 4.5, 0, 0, 0,
                "30分钟", "1km", "[]", "", "测试地址", 30.5, 114.3, 1, "[1]", 99, 1, 0, "", 0)));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(
                new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "", 30.5, 114.3)));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(
                new Goods(GOODS_ID, STORE_ID, "测试商品", "", 10, 10, "", 1, 0, 999, 0, 0, 4.5, "", false, 1, "")));
        when(goodsDao.deductStock(GOODS_ID, 1)).thenReturn(true);
    }

    private Order.OrderItem item() {
        return new Order.OrderItem(GOODS_ID, "测试商品", 10, 1, "");
    }

    private Order storedOrder(long id) {
        return new Order(id, "NO" + id, USER_ID, STORE_ID, "测试店", 0,
                "[]", "{}", 10, 0, 0, 10, "", 0, 0,
                LocalDateTime.now().format(FMT), "", "", "", "", "", 0);
    }

    /** Redis 不可用时下单必须继续（契约：加固不能变成下单不可用）。 */
    @Test
    @SuppressWarnings("unchecked")
    void orderSucceedsWhenRedisIsDown() {
        stubCommon();
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> ops = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(ops);
        // 模拟真实故障：bean 在，但连接被拒
        when(ops.setIfAbsent(anyString(), anyString(), any(Duration.class)))
                .thenThrow(new RedisConnectionFailureException("Unable to connect to Redis"));
        when(orderDao.insert(any(Order.class))).thenReturn(13L);
        when(orderDao.findById(13L)).thenReturn(Optional.of(new Order(13L, "NO13", USER_ID, STORE_ID, "测试店", 0,
                "[]", "{}", 10, 0, 0, 10, "", 0, 0, LocalDateTime.now().format(FMT), "", "", "", "", "", 0)));

        OrderService service = serviceWithRedis(redis);

        // 修复前：这里会抛 RedisConnectionFailureException（实测 500）
        Order.OrderView view = service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "",
                List.of(), "", "idem-key-1", List.of(), "");

        assertEquals(0, view.status(), "Redis 不可用时下单应照常成功，防重仍由数据库保证");
        org.mockito.Mockito.verify(orderDao).reserveCreateRequest(USER_ID, "idem-key-1");
        org.mockito.Mockito.verify(orderDao).bindCreateRequest(USER_ID, "idem-key-1", 13L);
    }

    /** Redis 超时同样只降级、不阻断下单。 */
    @Test
    @SuppressWarnings("unchecked")
    void orderSucceedsWhenRedisTimesOut() {
        stubCommon();
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> ops = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(ops);
        when(ops.setIfAbsent(anyString(), anyString(), any(Duration.class)))
                .thenThrow(new QueryTimeoutException("timeout"));
        when(orderDao.insert(any(Order.class))).thenReturn(13L);
        when(orderDao.findById(13L)).thenReturn(Optional.of(new Order(13L, "NO13", USER_ID, STORE_ID, "测试店", 0,
                "[]", "{}", 10, 0, 0, 10, "", 0, 0, LocalDateTime.now().format(FMT), "", "", "", "", "", 0)));

        OrderService service = serviceWithRedis(redis);

        Order.OrderView view = service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "",
                List.of(), "", "idem-key-2", List.of(), "");

        assertEquals(0, view.status());
    }

    /** Redis 命中进行中占位、数据库尚无完成映射时，明确提示稍后重试。 */
    @Test
    @SuppressWarnings("unchecked")
    void duplicateSubmitStillRejectedWhenRedisWorks() {
        stubCommon();
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> ops = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(ops);
        // setIfAbsent 返回 false = 键已存在 = 重复提交
        when(ops.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(false);

        OrderService service = serviceWithRedis(redis);

        BizException error = assertThrows(BizException.class, () ->
                service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "",
                        List.of(), "", "idem-key-3", List.of(), ""));

        assertEquals("订单正在提交中，请稍后重试", error.getMessage());
    }

    @Test
    @SuppressWarnings("unchecked")
    void redisDuplicateReturnsCompletedOrderAfterLostResponse() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> ops = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(ops);
        when(ops.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(false);
        when(orderDao.findCompletedCreateRequest(USER_ID, "lost-response")).thenReturn(Optional.of(13L));
        when(orderDao.findById(13L)).thenReturn(Optional.of(storedOrder(13L)));

        Order.OrderView replay = serviceWithRedis(redis).createOrder(USER_ID, STORE_ID, List.of(item()),
                ADDRESS_ID, 0, "", List.of(), "", "lost-response", List.of(), "");

        assertEquals(13L, replay.id());
        org.mockito.Mockito.verify(orderDao, org.mockito.Mockito.never()).reserveCreateRequest(org.mockito.ArgumentMatchers.anyLong(), anyString());
        org.mockito.Mockito.verifyNoInteractions(goodsDao, couponDao, storeDao);
    }
}
