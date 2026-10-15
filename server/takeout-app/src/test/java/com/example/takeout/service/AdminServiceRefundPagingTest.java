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

class AdminServiceRefundPagingTest {

    private final RefundDao refunds = mock(RefundDao.class);
    private final AdminService service = new AdminService(mock(StoreDao.class), mock(OrderDao.class),
            mock(UserDao.class), mock(GoodsDao.class), refunds, mock(OrderService.class), mock(AdminStatsDao.class),
            mock(HotDataCacheService.class), mock(com.example.takeout.service.mq.DomainEventPublisher.class),
            mock(PaymentRecordDao.class));

    @Test
    void normalizesFilterAndComputesPage() {
        when(refunds.countForAdmin("PENDING")).thenReturn(101);
        when(refunds.listForAdmin("PENDING", 100, 0L)).thenReturn(List.of());

        AdminService.RefundPage page = service.refunds("pending", 1, 500);

        verify(refunds).listForAdmin("PENDING", 100, 0L);
        assertEquals(101, page.total());
        assertEquals(100, page.pageSize());
        assertTrue(page.hasMore());
    }

    @Test
    void rejectsUnknownRefundStatus() {
        assertThrows(BizException.class, () -> service.refunds("UNKNOWN", 1, 50));
    }
}
