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
import com.example.takeout.model.Review;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderServiceSecurityTest {

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

    @Test
    void rejectsNonPositiveQuantity() {
        Store store = new Store(10, "测试店", "", 4.5, 0, 3, 0, "30分钟", "1km", "[]", "", 1, "[1]", 99, 1, 0, "");
        when(storeDao.findById(10)).thenReturn(Optional.of(store));
        when(addressDao.listByUser(1)).thenReturn(List.of(new Address(20, 1, "张三", "13800138000", "测试地址", 1, "")));

        Order.OrderItem item = new Order.OrderItem(100, "商品", 10, 0, "");
        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(1, 10, List.of(item), 20, 0, ""));

        assertEquals("商品数量必须大于 0", error.getMessage());
    }

    @Test
    void rejectsOrderDetailBelongingToAnotherUser() {
        Order order = new Order(7, "NO7", 2, 10, "测试店", 1, "[]", "{}", 10, 3, 0, 13,
                "", 0, 0, "", "", "", "", "");
        Store store = new Store(10, "测试店", "", 4.5, 0, 3, 0, "30分钟", "1km", "[]", "", 1, "[1]", 99, 1, 0, "");
        when(orderDao.findById(7)).thenReturn(Optional.of(order));
        when(storeDao.findById(10)).thenReturn(Optional.of(store));

        BizException error = assertThrows(BizException.class, () -> service.orderDetail(1, 0, 7));

        assertEquals(403, error.getCode());
    }

    @Test
    void rejectsGoodsFromAnotherStore() {
        Store store = new Store(10, "测试店", "", 4.5, 0, 3, 0, "30分钟", "1km", "[]", "", 1, "[1]", 99, 1, 0, "");
        Goods goods = new Goods(100, 11, "串店商品", "", 10, 10, "", 1, 0, 999, 0, 0, 4.5, "", 1, "");
        when(storeDao.findById(10)).thenReturn(Optional.of(store));
        when(addressDao.listByUser(1)).thenReturn(List.of(new Address(20, 1, "张三", "13800138000", "测试地址", 1, "")));
        when(goodsDao.findById(100)).thenReturn(Optional.of(goods));

        Order.OrderItem item = new Order.OrderItem(100, "串店商品", 10, 1, "");
        BizException error = assertThrows(BizException.class,
                () -> service.createOrder(1, 10, List.of(item), 20, 0, ""));

        assertEquals("订单包含其他店铺商品", error.getMessage());
    }

    @Test
    void confirmingDeliveredOrderSettlesMerchantOnlyOnce() {
        Order order = new Order(8, "NO8", 1, 10, "测试店铺", 4, "[]",
                "{\"addressId\":20,\"name\":\"张三\",\"phone\":\"13800138000\",\"detail\":\"宿舍\"}",
                20, 0, 0, 20, "", 0, 0, "2026-08-16 10:00:00", "2026-08-16 10:00:00", "", "",
                "2026-08-16 10:10:00");
        Store store = new Store(10, "测试店铺", "", 4.5, 0, 0, 0, "30分钟", "1km", "[]", "", 1, "[1]", 2, 1, 0, "");
        User merchant = new User(2, "商户", "", "13600136000", "", 1, 50, "now");
        when(orderDao.findById(8)).thenReturn(Optional.of(order));
        when(storeDao.findById(10)).thenReturn(Optional.of(store));
        when(userDao.findById(2)).thenReturn(Optional.of(merchant));
        when(orderDao.releaseEscrow(8)).thenReturn(true, false);

        service.confirmOrder(1, 8);

        verify(userDao).updateBalance(2, 70.0);
        BizException error = assertThrows(BizException.class, () -> service.confirmOrder(1, 8));
        assertEquals("订单款项已结算或退款，不能重复确认", error.getMessage());
    }

    @Test
    void rejectsReviewForGoodsNotInOrder() {
        Order order = completedOrder(9, 100, 1, 0);
        when(orderDao.findById(9)).thenReturn(Optional.of(order));
        when(userDao.findById(1)).thenReturn(Optional.of(testUser()));

        BizException error = assertThrows(BizException.class,
                () -> service.reviewOrder(1, 9, 999, 5, "不错", List.of()));

        assertEquals("评价商品不在该订单中", error.getMessage());
        verify(reviewDao, org.mockito.Mockito.never()).insert(
                org.mockito.Mockito.anyLong(), org.mockito.Mockito.anyLong(), org.mockito.Mockito.anyLong(),
                org.mockito.Mockito.anyString(), org.mockito.Mockito.anyInt(), org.mockito.Mockito.anyString(),
                org.mockito.Mockito.anyString(), org.mockito.Mockito.anyString());
        verify(orderDao, org.mockito.Mockito.never()).markReviewed(9);
    }

    @Test
    void rejectsReviewBeforeEscrowSettlement() {
        Order order = completedOrder(10, 100, 0, 0);
        when(orderDao.findById(10)).thenReturn(Optional.of(order));

        BizException error = assertThrows(BizException.class,
                () -> service.reviewOrder(1, 10, 100, 5, "不错", List.of()));

        assertEquals("确认收货并结算后才能评价商品", error.getMessage());
        verify(userDao, org.mockito.Mockito.never()).findById(1);
    }

    @Test
    void rejectsDuplicateOrderReview() {
        Order order = completedOrder(11, 100, 1, 1);
        when(orderDao.findById(11)).thenReturn(Optional.of(order));

        BizException error = assertThrows(BizException.class,
                () -> service.reviewOrder(1, 11, 100, 5, "不错", List.of()));

        assertEquals("该订单已评价", error.getMessage());
        verify(userDao, org.mockito.Mockito.never()).findById(1);
    }

    @Test
    void savesReviewAgainstSelectedOrderGoods() {
        Order order = completedOrder(12, 100, 1, 0);
        Review saved = new Review(88, 10, 100, 1, "测试用户", 5, "不错", "[]", "2026-08-16 11:00:00");
        when(orderDao.findById(12)).thenReturn(Optional.of(order));
        when(userDao.findById(1)).thenReturn(Optional.of(testUser()));
        when(reviewDao.insert(org.mockito.ArgumentMatchers.eq(10L), org.mockito.ArgumentMatchers.eq(100L),
                org.mockito.ArgumentMatchers.eq(1L), org.mockito.ArgumentMatchers.eq("测试用户"),
                org.mockito.ArgumentMatchers.eq(5), org.mockito.ArgumentMatchers.eq("不错"),
                org.mockito.ArgumentMatchers.eq("[]"), org.mockito.ArgumentMatchers.anyString()))
                .thenReturn(88L);
        when(reviewDao.listByStore(10)).thenReturn(List.of(saved));

        Review result = service.reviewOrder(1, 12, 100, 5, "不错", List.of());

        assertEquals(100, result.goodsId());
        verify(orderDao).markReviewed(12);
    }

    private Order completedOrder(long id, long goodsId, int escrowStatus, int reviewed) {
        String items = "[{\"goodsId\":" + goodsId + ",\"goodsName\":\"测试商品\",\"price\":12.5,\"quantity\":1,\"image\":\"\"}]";
        return new Order(id, "NO" + id, 1, 10, "测试店铺", 4, items,
                "{}", 12.5, 0, 0, 12.5, "", reviewed, escrowStatus,
                "2026-08-16 10:00:00", "2026-08-16 10:00:00", "", "",
                "2026-08-16 10:10:00");
    }

    private User testUser() {
        return new User(1, "测试用户", "", "13800138000", "", 0, 20, "2026-08-16 10:00:00");
    }
}
