package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.controller.AuthController;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round5LoginAdmissionTest {
    private static final String PASSWORD = "round-five-password";
    private static final String HASH = PasswordUtil.hash(PASSWORD);

    private static User user(String phone) {
        return new User(Long.parseLong(phone), "probe", "", phone, HASH, 0, 0, "now");
    }
    private static AuthController controller(AuthService auth, LoginRateLimiter limiter) {
        return new AuthController(auth, limiter, mock(TokenRevocationService.class), mock(RefreshTokenService.class),
                mock(SmsVerificationService.class), mock(PushTokenService.class));
    }
    private static MockHttpServletRequest source() {
        var request = new MockHttpServletRequest(); request.setRemoteAddr("192.0.2.201"); return request;
    }

    @Test void thirtySimultaneousValidLoginsCompleteWithout503() throws Exception {
        var users = mock(UserDao.class); var jwt = mock(JwtUtil.class);
        when(users.findByPhone(anyString())).thenAnswer(call -> Optional.of(user(call.getArgument(0))));
        when(jwt.generateToken(anyLong(), anyInt(), anyString())).thenReturn("token");
        var auth = new AuthService(users, jwt); auth.afterPropertiesSet();
        // Warm up the real PBKDF2 path before measuring a synchronized burst.
        for (int i = 0; i < 4; i++) auth.login("13800138000", PASSWORD, "USER");
        var start = new CountDownLatch(1); var ready = new CountDownLatch(30);
        var results = new ArrayList<Future<Integer>>(); long elapsed;
        try (var pool = Executors.newFixedThreadPool(30)) {
            for (int i = 0; i < 30; i++) {
                String phone = "1380013" + String.format(Locale.ROOT, "%04d", i);
                results.add(pool.submit(() -> {
                    ready.countDown(); start.await();
                    try { return "token".equals(auth.login(phone, PASSWORD, "USER").token()) ? 200 : 500; }
                    catch (BizException e) { return e.getCode(); }
                }));
            }
            assertTrue(ready.await(5, TimeUnit.SECONDS)); long begin = System.nanoTime(); start.countDown();
            var codes = new ArrayList<Integer>(); for (var result : results) codes.add(result.get(20, TimeUnit.SECONDS));
            elapsed = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - begin);
            System.out.println("[RT-26] burst=30 success=" + Collections.frequency(codes, 200)
                    + " busy503=" + Collections.frequency(codes, 503) + " elapsed-ms=" + elapsed);
            assertEquals(30, Collections.frequency(codes, 200), codes.toString());
        }
    }

    @Test void operatorsCanConfigureSixteenPermitsAndTenSecondsButInvalidValuesStillFail() {
        var runner = new org.springframework.boot.test.context.runner.ApplicationContextRunner()
                .withBean(UserDao.class, () -> mock(UserDao.class)).withBean(JwtUtil.class, () -> mock(JwtUtil.class))
                .withBean(SmsCodeVerifier.class, () -> mock(SmsCodeVerifier.class)).withUserConfiguration(AuthService.class);
        runner.withPropertyValues("takeout.security.rate-limit.login-verify-max-concurrent=16",
                "takeout.security.rate-limit.login-verify-wait-millis=10000")
                .run(context -> assertNull(context.getStartupFailure()));
        for (String invalid : List.of("takeout.security.rate-limit.login-verify-max-concurrent=0",
                "takeout.security.rate-limit.login-verify-max-concurrent=17",
                "takeout.security.rate-limit.login-verify-wait-millis=-1",
                "takeout.security.rate-limit.login-verify-wait-millis=10001")) {
            runner.withPropertyValues(invalid).run(context -> assertNotNull(context.getStartupFailure()));
        }
        System.out.println("[RT-26/config] permits=16 wait=10000 accepted; 0/17/-1/10001 rejected");
    }

    @Test void sixtyFiveBusyRequestsConsumeNeitherTotalBudgetNorDatabaseQueries() throws Exception {
        var users = mock(UserDao.class); var jwt = mock(JwtUtil.class);
        var auth = new AuthService(users, jwt);
        ReflectionTestUtils.setField(auth, "loginVerifyWaitMillis", 0); auth.afterPropertiesSet();
        var entered = new CountDownLatch(2); var release = new CountDownLatch(1);
        var lookupNumber = new java.util.concurrent.atomic.AtomicInteger();
        when(users.findByPhone(anyString())).thenAnswer(call -> {
            if (lookupNumber.incrementAndGet() <= 2) {
                entered.countDown(); assertTrue(release.await(10, TimeUnit.SECONDS));
            }
            return Optional.of(user(call.getArgument(0)));
        });
        when(jwt.generateToken(anyLong(), anyInt(), anyString())).thenReturn("token");
        var limiter = spy(new LoginRateLimiter(mock(ObjectProvider.class)));
        var controller = controller(auth, limiter);
        try (var pool = Executors.newFixedThreadPool(2)) {
            var first = pool.submit(() -> auth.login("13800138001", PASSWORD));
            var second = pool.submit(() -> auth.login("13800138002", PASSWORD));
            try {
                assertTrue(entered.await(5, TimeUnit.SECONDS)); clearInvocations(limiter, users);
                var codes = new ArrayList<Integer>();
                for (int i = 0; i < 65; i++) codes.add(assertThrows(BizException.class,
                        () -> controller.login(new AuthController.LoginRequest("13800138003", PASSWORD, "USER"), source())).getCode());
                long totals = mockingDetails(limiter).getInvocations().stream().filter(call ->
                        call.getMethod().getName().equals("recordAttempt") && Set.of("login-total", "login-account-total")
                                .contains(call.getArgument(0))).count();
                int queries = mockingDetails(users).getInvocations().size();
                System.out.println("[RT-27/28] busy=" + Collections.frequency(codes, 503) + " throttled="
                        + Collections.frequency(codes, 429) + " total-debits=" + totals + " lookup-calls=" + queries);
                assertEquals(65, Collections.frequency(codes, 503)); assertEquals(0, totals); assertEquals(0, queries);
            } finally { release.countDown(); }
            assertEquals("token", first.get(5, TimeUnit.SECONDS).token());
            assertEquals("token", second.get(5, TimeUnit.SECONDS).token());
        }
        clearInvocations(users);
        for (int i = 0; i < 30; i++) assertNotNull(controller.login(
                new AuthController.LoginRequest("13800138003", PASSWORD, "USER"), source()));
        assertEquals(30, mockingDetails(users).getInvocations().size());
        assertEquals(429, assertThrows(BizException.class, () -> controller.login(
                new AuthController.LoginRequest("13800138003", PASSWORD, "USER"), source())).getCode());
        System.out.println("[RT-27] after-saturation account-success=30 next=429 (original budget preserved)");
    }

    @Test void admittedControllerLoginLooksUpAccountExactlyOnce() {
        var users = mock(UserDao.class); var jwt = mock(JwtUtil.class);
        when(users.findByPhone("13800138000")).thenReturn(Optional.of(user("13800138000")));
        when(jwt.generateToken(anyLong(), anyInt(), anyString())).thenReturn("token");
        var auth = new AuthService(users, jwt); auth.afterPropertiesSet();
        var limiter = new LoginRateLimiter(mock(ObjectProvider.class));
        assertNotNull(controller(auth, limiter).login(new AuthController.LoginRequest("13800138000", PASSWORD, "USER"), source()));
        int calls = mockingDetails(users).getInvocations().size();
        System.out.println("[RT-28] successful-controller-login lookup-calls=" + calls);
        verify(users, times(1)).findByPhone("13800138000");
    }
}
