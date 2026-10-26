package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.model.User;
import com.example.takeout.security.*;
import com.example.takeout.service.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.mock.web.MockHttpServletRequest;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round3SourceLoginBudgetTest {
    private final AuthService auth = mock(AuthService.class);
    private final LoginRateLimiter limiter = new LoginRateLimiter(mock(ObjectProvider.class));
    private final AuthController controller = new AuthController(auth, limiter, mock(TokenRevocationService.class),
            mock(RefreshTokenService.class), mock(SmsVerificationService.class), mock(PushTokenService.class));
    private final MockHttpServletRequest source = new MockHttpServletRequest();

    private void prepare() {
        source.setRemoteAddr("192.0.2.170");
        AuthLoginStub.bind(auth, phone -> "account:" + phone);
        when(auth.login(anyString(), eq("good"), anyString())).thenAnswer(call -> new AuthService.LoginResult(
                "token", new User(7, "user", "", call.getArgument(0), "", 0, 0, "now")));
        when(auth.login(anyString(), eq("bad"), anyString())).thenThrow(new BizException("账号或密码错误"));
    }
    @Test void twelveSuccessfulUsersBehindOneNatDoNotConsumeFailureBudget() {
        prepare();
        for (int i = 0; i < 12; i++) {
            String phone = "13800138" + String.format("%03d", i);
            assertDoesNotThrow(() -> controller.login(new AuthController.LoginRequest(phone, "good", "USER"), source));
        }
        assertFalse(limiter.isBlocked("login", source.getRemoteAddr()));
        System.out.println("[RT-17] successful users behind one NAT=12 denied=0 failure-block=false");
    }
    @Test void interleavedSuccessfulLoginsDoNotClearNineFailures() {
        prepare();
        for (int i = 0; i < 9; i++) {
            String target = "13800138" + String.format("%03d", i);
            assertEquals(400, assertThrows(BizException.class, () -> controller.login(
                    new AuthController.LoginRequest(target, "bad", "USER"), source)).getCode());
            String own = "13900138" + String.format("%03d", i);
            assertDoesNotThrow(() -> controller.login(new AuthController.LoginRequest(own, "good", "USER"), source));
        }
        assertEquals(400, assertThrows(BizException.class, () -> controller.login(
                new AuthController.LoginRequest("13800138999", "bad", "USER"), source)).getCode());
        assertEquals(429, assertThrows(BizException.class, () -> controller.login(
                new AuthController.LoginRequest("13900138999", "good", "USER"), source)).getCode());
        System.out.println("[RT-17] failures=10 interleaved-successes=9 source-block=true success-reset=none");
    }
    @Test void sourceTotalBudgetStillBoundsConcurrentPrechecks() throws Exception {
        prepare();
        try (var pool = java.util.concurrent.Executors.newFixedThreadPool(16)) {
            var start = new java.util.concurrent.CountDownLatch(1);
            var admitted = new java.util.concurrent.atomic.AtomicInteger();
            var futures = new java.util.ArrayList<java.util.concurrent.Future<?>>();
            for (int i = 0; i < 80; i++) {
                String phone = "13800138" + String.format("%03d", i);
                futures.add(pool.submit(() -> {
                    try { start.await(); controller.login(new AuthController.LoginRequest(phone, "good", "USER"), source); admitted.incrementAndGet(); }
                    catch (BizException e) { assertEquals(429, e.getCode()); }
                    catch (InterruptedException e) { throw new RuntimeException(e); }
                }));
            }
            start.countDown(); for (var future : futures) future.get();
            assertEquals(60, admitted.get());
            System.out.println("[RT-17] concurrent successful users=80 admitted=60 total-only-denied=20");
        }
    }
}
