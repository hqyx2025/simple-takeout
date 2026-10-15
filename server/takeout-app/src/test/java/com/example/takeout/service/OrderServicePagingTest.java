package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderServicePagingTest {

    private final OrderDao orders = mock(OrderDao.class);
    private final OrderService service = new OrderService(orders, mock(StoreDao.class), mock(GoodsDao.class),
            mock(AddressDao.class), mock(CouponDao.class), mock(ReviewDao.class), mock(UserDao.class),
            mock(RefundDao.class), new ObjectMapper(), mock(CartItemMapper.class), mock(RiderDao.class),
            mock(GoodsSpecDao.class), mock(SeckillDao.class), mock(HotDataCacheService.class),
            mock(DomainEventPublisher.class), mock(ObjectProvider.class), mock(PaymentRecordDao.class));

    @Test
    void clampsPageSizeAndUsesLongOffsetForUserOrders() {
        when(orders.countByUser(7, 4)).thenReturn(240);
        when(orders.listByUser(7, 4, 100, 214748364600L)).thenReturn(List.of());

        OrderService.OrderPage page = service.userOrders(7, 4, Integer.MAX_VALUE, 1000);

        verify(orders).listByUser(7, 4, 100, 214748364600L);
        assertEquals(Integer.MAX_VALUE, page.page());
        assertEquals(100, page.pageSize());
        assertEquals(240, page.total());
        assertFalse(page.hasMore());
    }

    @Test
    void merchantPageHasNoNextPageWhenPageCoversTotal() {
        when(orders.countByMerchant(17, null)).thenReturn(20);
        when(orders.listByMerchant(17, null, 30, 0L)).thenReturn(List.of());

        OrderService.OrderPage page = service.merchantOrders(17, null, 0, 30);

        verify(orders).listByMerchant(17, null, 30, 0L);
        assertEquals(1, page.page());
        assertFalse(page.hasMore());
    }

    @Test
    void riderPageUsesRequestedOffsetAndRejectsInvalidUserStatus() {
        when(orders.countByRider(3)).thenReturn(50);
        when(orders.listByRider(3, 25, 25L)).thenReturn(List.of());

        OrderService.OrderPage page = service.riderOrders(3, 2, 25);
        assertEquals(50, page.total());
        assertFalse(page.hasMore());
        verify(orders).listByRider(3, 25, 25L);

        assertThrows(BizException.class, () -> service.userOrders(7, 9, 1, 30));
    }
}
