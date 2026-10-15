package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AdminStatsDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminServiceOrderPagingTest {

    private final OrderDao orders = mock(OrderDao.class);
    private final AdminService service = new AdminService(mock(StoreDao.class), orders, mock(UserDao.class),
            mock(GoodsDao.class), mock(RefundDao.class), mock(OrderService.class), mock(AdminStatsDao.class),
            mock(HotDataCacheService.class), mock(com.example.takeout.service.mq.DomainEventPublisher.class),
            mock(PaymentRecordDao.class));

    @Test
    void returnsFilteredPageMetadataAndOffset() {
        when(orders.countForAdmin(4)).thenReturn(101);
        when(orders.listForAdminWithRider(4, 50, 50L)).thenReturn(List.of());

        AdminService.OrderPage page = service.orders(4, 2, 50);

        verify(orders).listForAdminWithRider(4, 50, 50L);
        assertEquals(101, page.total());
        assertEquals(2, page.page());
        assertEquals(50, page.pageSize());
        assertTrue(page.hasMore());
    }

    @Test
    void rejectsUnknownOrderState() {
        assertThrows(BizException.class, () -> service.orders(9, 1, 50));
    }
}
