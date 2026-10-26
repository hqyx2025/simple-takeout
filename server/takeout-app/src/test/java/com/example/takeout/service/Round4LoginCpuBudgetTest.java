package com.example.takeout.service;

import com.example.takeout.common.*;
import com.example.takeout.controller.AuthController;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

class Round4LoginCpuBudgetTest {
    @Test void twoHeldVerificationsCause503WithoutStartingAThirdAndPermitsAreReusable() throws Exception {
        var users = mock(UserDao.class); var jwt = mock(JwtUtil.class);
        var auth = spy(new AuthService(users, jwt));
        org.springframework.test.util.ReflectionTestUtils.setField(auth, "loginVerifyWaitMillis", 200);
        when(jwt.generateToken(7, 0, "")).thenReturn("token");
        var entered = new CountDownLatch(2); var release = new CountDownLatch(1);
        var active = new AtomicInteger(); var peak = new AtomicInteger();
        var row = new AtomicReference<Optional<User>>(Optional.empty());
        when(users.findByPhone(anyString())).thenAnswer(call -> {
            peak.accumulateAndGet(active.incrementAndGet(), Math::max); entered.countDown();
            try { release.await(1, TimeUnit.SECONDS); return row.get(); }
            finally { active.decrementAndGet(); }
        });
        var limiter = new LoginRateLimiter(mock(ObjectProvider.class));
        var controller = new AuthController(auth, limiter, mock(TokenRevocationService.class),
                mock(RefreshTokenService.class), mock(SmsVerificationService.class), mock(PushTokenService.class));
        var mvc = MockMvcBuilders.standaloneSetup(controller).setControllerAdvice(new GlobalExceptionHandler()).build();
        java.util.function.Supplier<Integer> wrong = () -> {
            try { return mvc.perform(post("/api/auth/login").with(request -> { request.setRemoteAddr("192.0.2.210"); return request; })
                    .contentType(MediaType.APPLICATION_JSON).content("{\"phone\":\"13800138000\",\"password\":\"wrong-password\",\"loginType\":\"USER\"}"))
                    .andReturn().getResponse().getStatus(); }
            catch (Exception e) { throw new RuntimeException(e); }
        };
        try (var pool = Executors.newFixedThreadPool(2)) {
            var first = pool.submit(wrong::get); var second = pool.submit(wrong::get);
            try {
                assertTrue(entered.await(3, TimeUnit.SECONDS));
                long start = System.nanoTime(); int status = wrong.get();
                long waitMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);
                System.out.println("[RT-21] held=2 observed-peak=" + peak.get() + " saturated-status=" + status + " wait-ms=" + waitMs);
                assertEquals(503, status); assertEquals(2, peak.get()); assertTrue(waitMs < 800);
            } finally { release.countDown(); }
            assertEquals(400, first.get(5, TimeUnit.SECONDS)); assertEquals(400, second.get(5, TimeUnit.SECONDS));
        }
        row.set(Optional.of(new User(7, "user", "", "13800138000", PasswordUtil.hash("known-password"), 0, 0, "now")));
        assertEquals("token", auth.login("13800138000", "known-password", "USER").token());
        System.out.println("[RT-21] failed-work-released-permits=true later-correct-login=allowed");
    }

    @Test void knownAndMissingKeepComparablePbkdf2CostAndHmacAloneCannotHideIt() throws Exception {
        String hash = PasswordUtil.hash("known-password");
        for (int i = 0; i < 3; i++) { PasswordUtil.matchesForLogin("wrong", hash); PasswordUtil.matchesForLogin("wrong", null); }
        var known = new ArrayList<Long>(); var missing = new ArrayList<Long>();
        for (int i = 0; i < 7; i++) {
            long start = System.nanoTime(); PasswordUtil.matchesForLogin("wrong", hash); known.add(System.nanoTime() - start);
            start = System.nanoTime(); PasswordUtil.matchesForLogin("wrong", null); missing.add(System.nanoTime() - start);
        }
        double modernMs = median(known) / 1e6, absentMs = median(missing) / 1e6;
        assertTrue(Math.abs(modernMs - absentMs) / Math.max(modernMs, absentMs) < .10);
        var mac = javax.crypto.Mac.getInstance("HmacSHA256");
        mac.init(new javax.crypto.spec.SecretKeySpec(new byte[32], "HmacSHA256"));
        byte[] bytes = "fixed-probe".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        for (int i = 0; i < 1000; i++) mac.doFinal(bytes);
        long start = System.nanoTime(); for (int i = 0; i < 10_000; i++) mac.doFinal(bytes);
        double hmacMs = (System.nanoTime() - start) / 1e6 / 10_000;
        System.out.printf(Locale.ROOT, "[RT-21] modern=%.2fms missing=%.2fms difference=%.2f%% HMAC-only=%.5fms%n",
                modernMs, absentMs, 100 * Math.abs(modernMs - absentMs) / Math.max(modernMs, absentMs), hmacMs);
        assertTrue(modernMs > hmacMs * 10, "HMAC followed by real PBKDF2 cannot match HMAC-only cost");
    }
    @Test void databaseExceptionsDoNotLeakVerificationPermits() {
        var users = mock(UserDao.class); var auth = new AuthService(users, mock(JwtUtil.class));
        when(users.findByPhone(anyString())).thenThrow(new IllegalStateException("test DB unavailable"));
        for (int i = 0; i < 5; i++) assertThrows(IllegalStateException.class, () -> auth.login("13800138000", "wrong"));
        doReturn(Optional.empty()).when(users).findByPhone(anyString());
        assertEquals(400, assertThrows(BizException.class, () -> auth.login("13800138000", "wrong")).getCode());
    }
    @Test void runtimePropertyCanLowerTheVerificationCapAndInvalidBudgetsFailStartup() {
        var runner = new org.springframework.boot.test.context.runner.ApplicationContextRunner()
                .withBean(UserDao.class, () -> mock(UserDao.class)).withBean(JwtUtil.class, () -> mock(JwtUtil.class))
                .withBean(SmsCodeVerifier.class, () -> mock(SmsCodeVerifier.class)).withUserConfiguration(AuthService.class);
        for (String invalid : List.of("takeout.security.rate-limit.login-verify-max-concurrent=0",
                "takeout.security.rate-limit.login-verify-max-concurrent=17", "takeout.security.rate-limit.login-verify-wait-millis=10001")) {
            runner.withPropertyValues(invalid).run(context -> assertNotNull(context.getStartupFailure()));
        }
        runner.withPropertyValues("takeout.security.rate-limit.login-verify-max-concurrent=1", "takeout.security.rate-limit.login-verify-wait-millis=200").run(context -> {
            assertNull(context.getStartupFailure());
            var users = context.getBean(UserDao.class); var auth = context.getBean(AuthService.class);
            var entered = new CountDownLatch(1); var release = new CountDownLatch(1);
            when(users.findByPhone(anyString())).thenAnswer(call -> { entered.countDown(); release.await(1, TimeUnit.SECONDS); return Optional.empty(); });
            try (var pool = Executors.newSingleThreadExecutor()) {
                var held = pool.submit(() -> assertThrows(BizException.class, () -> auth.login("13800138000", "wrong")));
                try {
                    assertTrue(entered.await(3, TimeUnit.SECONDS));
                    assertEquals(503, assertThrows(BizException.class, () -> auth.login("13800138000", "wrong")).getCode());
                } finally { release.countDown(); }
                assertEquals(400, held.get(5, TimeUnit.SECONDS).getCode());
            }
            System.out.println("[RT-21/config] runtime concurrency=1 enforced; invalid 0/17/10001 budgets rejected at startup");
        });
    }
    private static long median(List<Long> values) { return values.stream().sorted().toList().get(values.size() / 2); }
}
