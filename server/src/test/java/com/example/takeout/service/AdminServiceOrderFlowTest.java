package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AdminStatsDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Order;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 管理端订单流转的「出餐」必须支持 ready。
 *
 * <p>管理端走的是 AdminController → AdminService.orderFlow 这条独立分支，不复用 OrderService.merchantFlow。
 * 因此把前端管理端的「出餐」改成 ready 时，如果后端 AdminService 没有 ready 分支，就会直接抛
 * 「不支持的订单操作：ready」——比原来更糟。本测试钉住 admin 端与商户端在出餐语义上一致。
 */
class AdminServiceOrderFlowTest {

    private static final long ORDER_ID = 500L;

    private final OrderDao orderDao = mock(OrderDao.class);
    private final OrderService orderService = mock(OrderService.class);
    private final AdminService service = new AdminService(mock(StoreDao.class), orderDao, mock(UserDao.class),
            mock(GoodsDao.class), mock(RefundDao.class), orderService, mock(AdminStatsDao.class),
            mock(HotDataCacheService.class), mock(com.example.takeout.service.mq.DomainEventPublisher.class));

    private Order storedOrder(int status) {
        return new Order(ORDER_ID, "NO500", 1L, 10L, "测试店", status, "[]",
                "{\"addressId\":1,\"name\":\"张三\",\"phone\":\"138\",\"detail\":\"地址\"}",
                10, 5, 0, 15, "", 0, 0, "2026-09-15 10:00:00",
                "2026-09-15 10:01:00", "", "", "", "", 0);
    }

    @Test
    void adminReadyWritesReadyTimeInsteadOfPushingOrderToDelivering() {
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(2)));
        when(orderDao.markReady(eq(ORDER_ID), anyString())).thenReturn(true);

        service.orderFlow(ORDER_ID, "ready");

        verify(orderDao).markReady(eq(ORDER_ID), anyString());
        // 出餐不得走 deliver：那会让订单永久跳过骑手待取餐池
        verify(orderDao, never()).merchantDeliver(anyLong(), anyString());
        verify(orderDao, never()).updateStatusFrom(anyLong(), eq(2), eq(3), anyString(), anyString());
    }

    @Test
    void adminReadyIsRejectedWhenAlreadyReady() {
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(2)));
        when(orderDao.markReady(eq(ORDER_ID), anyString())).thenReturn(false);

        BizException error = assertThrows(BizException.class, () -> service.orderFlow(ORDER_ID, "ready"));
        assertTrue(error.getMessage().contains("已出餐"), error.getMessage());
    }

    @Test
    void adminCannotDeliverOrderAlreadyTakenByRider() {
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(2)));
        when(orderDao.findRiderId(ORDER_ID)).thenReturn(77L);

        BizException error = assertThrows(BizException.class, () -> service.orderFlow(ORDER_ID, "deliver"));
        assertTrue(error.getMessage().contains("骑手"), error.getMessage());
        verify(orderDao, never()).merchantDeliver(anyLong(), anyString());
    }

    @Test
    void adminDeliverStillWorksForSelfDeliveryWithoutRider() {
        when(orderDao.findById(ORDER_ID)).thenReturn(Optional.of(storedOrder(2)));
        when(orderDao.findRiderId(ORDER_ID)).thenReturn(0L);
        when(orderDao.merchantDeliver(eq(ORDER_ID), anyString())).thenReturn(true);

        service.orderFlow(ORDER_ID, "deliver");

        verify(orderDao).merchantDeliver(eq(ORDER_ID), anyString());
        assertEquals(0L, orderDao.findRiderId(ORDER_ID));
    }
}