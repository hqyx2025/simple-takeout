package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.service.AdminService;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;

class AdminControllerSecurityTest {

    @Test
    void userRoleCannotReadAdminCategories() {
        AdminController controller = new AdminController(mock(AdminService.class));

        BizException error = assertThrows(BizException.class,
                () -> controller.categories(0));

        assertEquals(403, error.getCode());
    }

    @Test
    void merchantRoleCannotReadAdminCategories() {
        AdminController controller = new AdminController(mock(AdminService.class));

        BizException error = assertThrows(BizException.class,
                () -> controller.categories(1));

        assertEquals(403, error.getCode());
    }

    @Test
    void nonAdminCannotManageProducts() {
        AdminController controller = new AdminController(mock(AdminService.class));

        BizException error = assertThrows(BizException.class,
                () -> controller.products(1, null, null, 1, 50));

        assertEquals(403, error.getCode());
    }

    @Test
    void nonAdminCannotReadPagedUsers() {
        AdminController controller = new AdminController(mock(AdminService.class));

        BizException error = assertThrows(BizException.class,
                () -> controller.usersPage(1, null, null, null, 1, 50));

        assertEquals(403, error.getCode());
    }

    @Test
    void nonAdminCannotReadPagedOrdersOrRefunds() {
        AdminController controller = new AdminController(mock(AdminService.class));

        assertEquals(403, assertThrows(BizException.class,
                () -> controller.ordersPage(1, null, 1, 50)).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> controller.refundsPage(1, null, 1, 50)).getCode());
    }

    @Test
    void nonAdminCannotReadStatistics() {
        AdminController controller = new AdminController(mock(AdminService.class));

        BizException error = assertThrows(BizException.class,
                () -> controller.statistics(0, 10));

        assertEquals(403, error.getCode());
    }

    @Test
    void nonAdminCannotChangeStoreRecommendation() {
        AdminController controller = new AdminController(mock(AdminService.class));

        BizException error = assertThrows(BizException.class,
                () -> controller.updateStoreRecommended(0, 1,
                        new AdminController.StoreRecommendRequest(1)));

        assertEquals(403, error.getCode());
    }

    @Test
    void nonAdminCannotReadOrManagePlatformMarketing() {
        AdminController controller = new AdminController(mock(AdminService.class));

        assertEquals(403, assertThrows(BizException.class,
                () -> controller.marketingActivities(1, null, null)).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> controller.updateMarketingActivityStatus(1, 1,
                        new AdminController.StoreStatusRequest(0))).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> controller.deleteMarketingActivity(1, 1)).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> controller.marketingSeckills(1, null, null)).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> controller.updateMarketingSeckillStatus(1, 1,
                        new AdminController.StoreStatusRequest(0))).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> controller.deleteMarketingSeckill(1, 1)).getCode());
    }
}
