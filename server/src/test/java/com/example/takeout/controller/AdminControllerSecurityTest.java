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
                () -> controller.products(1, null, null));

        assertEquals(403, error.getCode());
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
}
