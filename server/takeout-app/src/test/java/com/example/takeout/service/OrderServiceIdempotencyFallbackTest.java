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
    void databaseRejectsReplayBeforeReservingStockEvenWithoutRedis() {
        org.mockito.Mockito.doThrow(new org.springframework.dao.DuplicateKeyException("PRIMARY"))
                .when(orderDao).reserveCreateRequest(USER_ID, "committed-request");

        BizException error = assertThrows(BizException.class, () -> serviceWithRedis(null).createOrder(
                USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of(), "",
                " committed-request ", List.of(), ""));

        assertEquals("订单已提交，请勿重复操作", error.getMessage());
        org.mockito.Mockito.verifyNoInteractions(goodsDao, couponDao, storeDao);
        org.mockito.Mockito.verify(orderDao, org.mockito.Mockito.never()).insert(any(Order.class));
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
                "30分钟", "1km", "[]", "", 1, "[1]", 99, 1, 0, "")));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(
                new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(
                new Goods(GOODS_ID, STORE_ID, "测试商品", "", 10, 10, "", 1, 0, 999, 0, 0, 4.5, "", false, 1, "")));
        when(goodsDao.deductStock(GOODS_ID, 1)).thenReturn(true);
    }

    private Order.OrderItem item() {
        return new Order.OrderItem(GOODS_ID, "测试商品", 10, 1, "");
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

    /** 但真·重复提交仍必须被拦住——降级不能把防重功能整个吃掉。 */
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

        assertEquals("订单正在提交中，请勿重复操作", error.getMessage(),
                "Redis 正常时重复提交必须被拦，且提示文案不变（前端依赖它）");
    }
}
