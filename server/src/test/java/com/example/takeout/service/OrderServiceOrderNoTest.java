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
import org.mockito.ArgumentCaptor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.UncategorizedSQLException;

import java.sql.SQLException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 订单号唯一性契约测试。
 *
 * <p>把订单号从「秒级时间戳 + 4 位随机数」换成雪花 ID 之后，必须钉住两件事：
 * ① 订单号格式仍是纯数字且在列宽内（前端只当字符串展示，但不能超 VARCHAR(32)）；
 * ② 万一仍撞上 {@code orders.order_no} 唯一键，要换号重试一次而不是直接把失败抛给用户。</p>
 */
class OrderServiceOrderNoTest {

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
            mock(DomainEventPublisher.class),
            mock(org.springframework.beans.factory.ObjectProvider.class), mock(PaymentRecordDao.class));

    private static final long STORE_ID = 10L;
    private static final long GOODS_ID = 100L;
    private static final long ADDRESS_ID = 20L;
    private static final long USER_ID = 1L;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

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

    /** 唯一键冲突（order_no）——按 MySQL 实际报错文本构造。 */
    private DuplicateKeyException orderNoConflict() {
        return new DuplicateKeyException(
                "Duplicate entry '1234567890123456789' for key 'orders.order_no'",
                new UncategorizedSQLException("StatementCallback",
                        "INSERT INTO orders(...) VALUES(...)",
                        new SQLException("Duplicate entry '123' for key 'orders.order_no'")));
    }

    @Test
    void generatedOrderNoIsDigitsOnlyAndFitsColumnWidth() {
        stubCommon();
        ArgumentCaptor<Order> captor = ArgumentCaptor.forClass(Order.class);
        when(orderDao.insert(captor.capture())).thenReturn(13L);
        when(orderDao.findById(13L)).thenReturn(Optional.of(new Order(13L, "x", USER_ID, STORE_ID, "测试店", 0,
                "[]", "{}", 10, 0, 0, 10, "", 0, 0, LocalDateTime.now().format(FMT), "", "", "", "", "", 0)));

        service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of());

        String orderNo = captor.getValue().orderNo();
        assertTrue(orderNo.matches("\\d+"), "订单号必须只含数字：" + orderNo);
        assertTrue(orderNo.length() <= 32, "订单号必须能放进 orders.order_no VARCHAR(32)：" + orderNo);
        // 雪花 ID 至少 18 位（当前纪元下），远大于旧格式的 18 位时间戳+4 随机数
        assertTrue(orderNo.length() >= 15, "订单号应是雪花 ID 而非旧的时间戳+随机数格式：" + orderNo);
    }

    @Test
    void retriesOnceWithNewOrderNoOnUniqueConflict() {
        stubCommon();
        ArgumentCaptor<Order> captor = ArgumentCaptor.forClass(Order.class);
        // 第一次冲突，第二次成功
        when(orderDao.insert(captor.capture())).thenThrow(orderNoConflict()).thenReturn(13L);
        when(orderDao.findById(13L)).thenReturn(Optional.of(new Order(13L, "x", USER_ID, STORE_ID, "测试店", 0,
                "[]", "{}", 10, 0, 0, 10, "", 0, 0, LocalDateTime.now().format(FMT), "", "", "", "", "", 0)));

        service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of());

        List<Order> attempts = captor.getAllValues();
        assertEquals(2, attempts.size(), "唯一键冲突后必须重试一次");
        assertNotEquals(attempts.get(0).orderNo(), attempts.get(1).orderNo(),
                "重试必须换一个新的订单号，否则必然再次冲突");
    }

    @Test
    void failsWithReadableMessageWhenRetryAlsoConflicts() {
        stubCommon();
        // 两次都冲突：不能无限重试，也不能把 SQL 异常原文抛给用户
        when(orderDao.insert(any(Order.class))).thenThrow(orderNoConflict());

        BizException error = assertThrows(BizException.class, () ->
                service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of()));

        assertTrue(error.getMessage().contains("订单号"), "应给出可读提示：" + error.getMessage());
        verify(orderDao, times(2)).insert(any(Order.class));
    }

    @Test
    void doesNotRetryForUnrelatedUniqueConflict() {
        stubCommon();
        // 冲突来自别的唯一键（如秒杀一人一单）时不得换号重试——那是掩盖真实错误
        when(orderDao.insert(any(Order.class))).thenThrow(new DuplicateKeyException(
                "Duplicate entry '1-5' for key 'seckill_orders.uk_user_seckill'",
                new UncategorizedSQLException("StatementCallback", "INSERT INTO seckill_orders(...)",
                        new SQLException("Duplicate entry '1-5' for key 'seckill_orders.uk_user_seckill'"))));

        assertThrows(DuplicateKeyException.class, () ->
                service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of()));

        verify(orderDao, times(1)).insert(any(Order.class));
    }

    @Test
    void consecutiveOrdersGetDistinctOrderNumbers() {
        stubCommon();
        ArgumentCaptor<Order> captor = ArgumentCaptor.forClass(Order.class);
        when(orderDao.insert(captor.capture())).thenReturn(13L);
        when(orderDao.findById(13L)).thenReturn(Optional.of(new Order(13L, "x", USER_ID, STORE_ID, "测试店", 0,
                "[]", "{}", 10, 0, 0, 10, "", 0, 0, LocalDateTime.now().format(FMT), "", "", "", "", "", 0)));

        // 同一秒内连下 200 单：旧实现（4 位随机数）在此规模下几乎必然碰撞
        for (int i = 0; i < 200; i++) {
            service.createOrder(USER_ID, STORE_ID, List.of(item()), ADDRESS_ID, 0, "", List.of());
        }

        long distinct = captor.getAllValues().stream().map(Order::orderNo).distinct().count();
        assertEquals(200, distinct, "同一秒内 200 笔订单的订单号必须全不相同");
    }
}