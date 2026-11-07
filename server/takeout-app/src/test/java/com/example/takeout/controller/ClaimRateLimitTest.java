package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.model.Rider;
import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.service.OrderService;
import com.example.takeout.service.RiderService;
import com.example.takeout.service.UserCenterService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class ClaimRateLimitTest {
    @Test
    void couponLimitRejectsBeforeBusinessAndDoesNotBlockAnotherAccount() {
        var service = mock(UserCenterService.class);
        var controller = new UserCenterController(service, new LoginRateLimiter(mock(ObjectProvider.class)));
        var request = new UserCenterController.ClaimCouponRequest(0, "", 10, 2);
        for (int i = 0; i < 15; i++) controller.claim(1, request);
        assertEquals(429, assertThrows(BizException.class, () -> controller.claim(1, request)).getCode());
        controller.claim(2, request);
        verify(service, times(15)).claimCoupon(1, 0, "", 10, 2);
        verify(service).claimCoupon(2, 0, "", 10, 2);
    }

    @Test
    void riderLimitRejectsBeforeProfileOrAssignmentAndKeepsRoleGuard() {
        var riders = mock(RiderService.class);
        var orders = mock(OrderService.class);
        var controller = new RiderController(riders, orders, new LoginRateLimiter(mock(ObjectProvider.class)));
        when(riders.profile(1)).thenReturn(new Rider(77, 1, "rider", "", 1, 0, 0, 1, 25000,
                30.5, 114.3, "", ""));
        assertEquals(403, assertThrows(BizException.class, () -> controller.grab(1, 0, 900)).getCode());
        verifyNoInteractions(riders, orders);
        for (int i = 0; i < 30; i++) controller.grab(1, 3, 900);
        assertEquals(429, assertThrows(BizException.class, () -> controller.grab(1, 3, 900)).getCode());
        verify(orders, times(30)).riderGrab(77, 900);
        verify(riders, times(30)).profile(1);
    }

    @Test
    void parallelCouponRequestsCannotExceedAccountBudget() throws Exception {
        var service = mock(UserCenterService.class);
        var controller = new UserCenterController(service, new LoginRateLimiter(mock(ObjectProvider.class)));
        var start = new java.util.concurrent.CountDownLatch(1);
        try (var pool = java.util.concurrent.Executors.newFixedThreadPool(32)) {
            var tasks = new java.util.ArrayList<java.util.concurrent.Future<?>>();
            for (int i = 0; i < 32; i++) tasks.add(pool.submit(() -> {
                assertTrue(start.await(5, java.util.concurrent.TimeUnit.SECONDS));
                try { controller.claim(1, new UserCenterController.ClaimCouponRequest(0, "", 10, 2)); }
                catch (BizException e) { assertEquals(429, e.getCode()); }
                return null;
            }));
            start.countDown();
            for (var task : tasks) task.get(5, java.util.concurrent.TimeUnit.SECONDS);
        } finally { start.countDown(); }
        verify(service, times(15)).claimCoupon(anyLong(), anyLong(), anyString(), anyDouble(), anyDouble());
    }
}
