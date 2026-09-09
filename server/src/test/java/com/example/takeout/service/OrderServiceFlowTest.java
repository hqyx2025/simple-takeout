package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.CouponDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.ReviewDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Address;
import com.example.takeout.model.Goods;
import com.example.takeout.model.Order;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** 订单业务闭环测试：下单前置校验、余额扣款、托管入账、取消退款幂等。 */
class OrderServiceFlowTest {

    private final OrderDao orderDao = mock(OrderDao.class);
    private final StoreDao storeDao = mock(StoreDao.class);
    private final GoodsDao goodsDao = mock(GoodsDao.class);
    private final AddressDao addressDao = mock(AddressDao.class);
    private final CouponDao couponDao = mock(CouponDao.class);
    private final ReviewDao reviewDao = mock(ReviewDao.class);
    private final UserDao userDao = mock(UserDao.class);
    private final RefundDao refundDao = mock(RefundDao.class);
    private final OrderService service = new OrderService(orderDao, storeDao, goodsDao, addressDao,
            couponDao, reviewDao, userDao, refundDao, new ObjectMapper());

    private static final long STORE_ID = 10L;
    private static final long GOODS_ID = 100L;
    private static final long ADDRESS_ID = 20L;
    private static final long USER_ID = 1L;

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

    private void stubCommon(double price, double minOrder, double deliveryFee) {
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore(minOrder, deliveryFee)));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(shelfGoods(price, STORE_ID)));
        when(userDao.findById(USER_ID)).thenReturn(Optional.of(user(50)));
        when(goodsDao.deductStock(GOODS_ID, 1)).thenReturn(true);
    }

    @Test
    void createsOrderDeductsBalanceAndEntersEscrow() {
        stubCommon(10, 0, 3);
        when(orderDao.insert(org.mockito.ArgumentMatchers.any(Order.class))).thenReturn(13L);
        String items = "[{\"goodsId\":100,\"goodsName\":\"测试商品\",\"price\":10.0,\"quantity\":1,\"image\":\"\"}]";
        String address = "{\"addressId\":20,\"name\":\"张三\",\"phone\":\"13800138000\",\"detail\":\"测试地址\"}";
        Order saved = new Order(13, "NO13", USER_ID, STORE_ID, "测试店", 1, items, address, 10, 3, 0, 13,
                "", 0, 0, "2026-08-16 10:00:00", "2026-08-16 10:00:00", "", "", "");
        when(orderDao.findById(13)).thenReturn(Optional.of(saved));

        Order.OrderView view = service.createOrder(USER_ID, STORE_ID,
                List.of(new Order.OrderItem(GOODS_ID, "测试商品", 10, 1, "")), ADDRESS_ID, 0, "", List.of());

        assertEquals(1, view.status());
        assertEquals(0, view.escrowStatus());
        assertEquals(13.0, view.payAmount(), 0.001);
        verify(userDao).updateBalance(eq(USER_ID), eq(37.0));
        verify(goodsDao).deductStock(GOODS_ID, 1);
        verify(storeDao).updateMonthlySales(STORE_ID, 1);
        verify(orderDao).insert(org.mockito.ArgumentMatchers.argThat(o ->
                o.status() == 1 && o.escrowStatus() == 0 && o.payAmount() == 13.0));
    }

    @Test
    void rejectsOrderWhenBalanceInsufficient() {
        stubCommon(10, 0, 3);
        when(userDao.findById(USER_ID)).thenReturn(Optional.of(user(5)));

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID,
                        List.of(new Order.OrderItem(GOODS_ID, "测试商品", 10, 1, "")), ADDRESS_ID, 0, "", List.of()));

        assertEquals("余额不足，请先充值", error.getMessage());
        verify(orderDao, never()).insert(org.mockito.ArgumentMatchers.any(Order.class));
        verify(goodsDao, never()).deductStock(org.mockito.ArgumentMatchers.anyLong(), org.mockito.ArgumentMatchers.anyInt());
    }

    @Test
    void rejectsOrderBelowMinimumOrder() {
        stubCommon(10, 20, 3);

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID,
                        List.of(new Order.OrderItem(GOODS_ID, "测试商品", 10, 1, "")), ADDRESS_ID, 0, "", List.of()));

        assertEquals("未达到店铺起送价（满20元起送）", error.getMessage());
        verify(orderDao, never()).insert(org.mockito.ArgumentMatchers.any(Order.class));
    }

    @Test
    void rejectsOrderWhenStoreClosed() {
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(
                new Store(STORE_ID, "测试店", "", 4.5, 0, 3, 0, "30分钟", "1km", "[]", "", 1, "[1]", 99, 0, 0, "")));
        when(addressDao.listByUser(USER_ID)).thenReturn(List.of(new Address(ADDRESS_ID, USER_ID, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(GOODS_ID)).thenReturn(Optional.of(shelfGoods(10, STORE_ID)));

        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(USER_ID, STORE_ID,
                        List.of(new Order.OrderItem(GOODS_ID, "测试商品", 10, 1, "")), ADDRESS_ID, 0, "", List.of()));

        assertEquals("店铺当前未营业", error.getMessage());
        verify(orderDao, never()).insert(org.mockito.ArgumentMatchers.any(Order.class));
    }

    @Test
    void cancelRefundsBalanceAndRestoresStockOnce() {
        String items = "[{\"goodsId\":100,\"goodsName\":\"测试商品\",\"price\":10.0,\"quantity\":1,\"image\":\"\"}]";
        String address = "{\"addressId\":20,\"name\":\"张三\",\"phone\":\"13800138000\",\"detail\":\"测试地址\"}";
        Order order = new Order(7, "NO7", USER_ID, STORE_ID, "测试店", 1, items, address, 10, 3, 0, 13,
                "", 0, 0, "2026-08-16 10:00:00", "2026-08-16 10:00:00", "", "", "");
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
}
