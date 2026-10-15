package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.service.OrderService;
import com.example.takeout.service.RiderService;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;

class OrderListPagingSecurityTest {

    @Test
    void onlyMerchantRoleCanReadMerchantPage() {
        var controller = new OrderController(mock(OrderService.class), mock(LoginRateLimiter.class));

        BizException error = assertThrows(BizException.class,
                () -> controller.merchantOrdersPage(9, 0, null, 1, 30));

        assertEquals(403, error.getCode());
    }

    @Test
    void onlyRiderRoleCanReadRiderPage() {
        var controller = new RiderController(mock(RiderService.class), mock(OrderService.class));

        BizException error = assertThrows(BizException.class,
                () -> controller.myOrdersPage(9, 0, 1, 30));

        assertEquals(403, error.getCode());
    }
}
