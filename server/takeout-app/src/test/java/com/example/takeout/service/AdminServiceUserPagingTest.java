package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AdminStatsDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.AdminUser;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminServiceUserPagingTest {

    private final UserDao users = mock(UserDao.class);
    private final AdminService service = new AdminService(mock(StoreDao.class), mock(OrderDao.class), users,
            mock(GoodsDao.class), mock(RefundDao.class), mock(OrderService.class), mock(AdminStatsDao.class),
            mock(HotDataCacheService.class), mock(com.example.takeout.service.mq.DomainEventPublisher.class),
            mock(PaymentRecordDao.class));

    @Test
    void returnsRequestedPageAndMoreFlag() {
        when(users.countForAdmin(1, 0, "shop")).thenReturn(120);
        when(users.listForAdmin(1, 0, "shop", 50, 50)).thenReturn(List.of(user(3)));

        AdminService.UserPage page = service.users(1, 0, "shop", 2, 50);

        verify(users).listForAdmin(1, 0, "shop", 50, 50);
        assertEquals(120, page.total());
        assertEquals(2, page.page());
        assertEquals(50, page.pageSize());
        assertTrue(page.hasMore());
        assertEquals(3, page.list().get(0).id());
    }

    @Test
    void clampsPageSizeAndNeverOverflowsOffset() {
        when(users.countForAdmin(null, null, null)).thenReturn(0);
        when(users.listForAdmin(null, null, null, 100, 214748364600L)).thenReturn(List.of());

        AdminService.UserPage page = service.users(null, null, null, Integer.MAX_VALUE, 500);

        verify(users).listForAdmin(null, null, null, 100, 214748364600L);
        assertEquals(100, page.pageSize());
        assertFalse(page.hasMore());
    }

    @Test
    void rejectsAdminRoleAsUserFilter() {
        BizException error = assertThrows(BizException.class, () -> service.users(2, null, null, 1, 50));

        assertEquals("用户角色筛选不合法", error.getMessage());
    }

    private AdminUser user(long id) {
        return new AdminUser(id, "test", "13800138000", 1, 1, 0, 1, "2026-01-01 00:00:00");
    }
}
