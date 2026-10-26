package com.example.takeout.security;

import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StringRedisTemplate;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.never;

/**
 * 登录限流：本地原子准入、共享预算拒绝及 Redis 不可用时的保护。
 */
class LoginRateLimiterTest {
    @Test void fullLocalTableDoesNotRejectUnrelatedActionsOrBypassExistingBlocks() {
        var limiter = new LoginRateLimiter(provider(null));
        for (int i = 0; i < 10_000; i++) limiter.recordAttempt("login-account-fail", "unknown:" + i);
        for (int i = 0; i < 5; i++) limiter.recordAttempt("payment-password", "u7");
        assertEquals(429, org.junit.jupiter.api.Assertions.assertThrows(com.example.takeout.common.BizException.class,
                () -> limiter.recordAttempt("payment-password", "u7")).getCode());
        limiter.recordAttempt("payment-password-set", "u7");
        limiter.recordAttempt("upload", "u8");
        org.junit.jupiter.api.Assertions.assertFalse(limiter.isBlocked("register", "192.0.2.10"));
        limiter.recordAttempt("register", "192.0.2.10");
    }

    @Test void paymentFailureBudgetCannotBlockSettingThePaymentPassword() {
        var limiter = new LoginRateLimiter(provider(null));
        for (int i = 0; i < 5; i++) limiter.recordAttempt("payment-password", "u7");
        assertTrue(limiter.isBlocked("payment-password", "u7"));
        limiter.recordAttempt("payment-password-set", "u7");
        assertFalse(limiter.isBlocked("payment-password-set", "u7"));
    }

    @Test
    void simultaneousRequestsCannotAllPassTheSeparatePrecheck() throws Exception {
        LoginRateLimiter limiter = new LoginRateLimiter(provider(null));
        var checked = new java.util.concurrent.CountDownLatch(32);
        var proceed = new java.util.concurrent.CountDownLatch(1);
        var admitted = new java.util.concurrent.atomic.AtomicInteger();
        try (var pool = java.util.concurrent.Executors.newFixedThreadPool(32)) {
            var futures = new java.util.ArrayList<java.util.concurrent.Future<?>>();
            for (int i = 0; i < 32; i++) futures.add(pool.submit(() -> {
                boolean blocked = limiter.isBlocked("payment-password", "u7");
                checked.countDown();
                try {
                    org.junit.jupiter.api.Assertions.assertTrue(proceed.await(5, java.util.concurrent.TimeUnit.SECONDS));
                    if (!blocked) {
                        try {
                            limiter.recordAttempt("payment-password", "u7");
                            admitted.incrementAndGet();
                        } catch (com.example.takeout.common.BizException e) {
                            org.junit.jupiter.api.Assertions.assertEquals(429, e.getCode());
                        }
                    }
                } catch (InterruptedException e) { throw new RuntimeException(e); }
            }));
            org.junit.jupiter.api.Assertions.assertTrue(checked.await(5, java.util.concurrent.TimeUnit.SECONDS));
            proceed.countDown();
            for (var future : futures) future.get(5, java.util.concurrent.TimeUnit.SECONDS);
        } finally { proceed.countDown(); }
        assertEquals(5, admitted.get(), "并发通过预检后，计数阶段也必须原子拒绝超额请求");
    }

    @SuppressWarnings("unchecked")
    private ObjectProvider<StringRedisTemplate> provider(StringRedisTemplate redis) {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);
        return provider;
    }

    @Test
    void unavailableRedisStartsWithAnUnblockedLocalWindow() {
        LoginRateLimiter limiter = new LoginRateLimiter(provider(null));

        assertFalse(limiter.isBlocked("login", "1.1.1.1"));
        limiter.recordAttempt("login", "1.1.1.1");
        limiter.reset("login", "1.1.1.1");
    }

    @Test
    void reportsBlockedWhenBlockMarkerExists() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        when(redis.hasKey("takeout:rl:login:1.1.1.1:blocked")).thenReturn(true);

        assertTrue(new LoginRateLimiter(provider(redis)).isBlocked("login", "1.1.1.1"));
    }

    @Test
    void sharedRedisRejectionIsNotSwallowedAsAnOutage() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(org.springframework.data.redis.core.script.RedisScript.class),
                any(java.util.List.class), anyString(), anyString(), anyString())).thenReturn(0L);
        var error = org.junit.jupiter.api.Assertions.assertThrows(com.example.takeout.common.BizException.class,
                () -> new LoginRateLimiter(provider(redis)).recordAttempt("login", "192.0.2.10"));
        assertEquals(429, error.getCode());
    }

    @Test
    void blocksIpWhenAttemptsReachLimit() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        LoginRateLimiter limiter = new LoginRateLimiter(provider(redis));
        for (int i = 0; i < 10; i++) limiter.recordAttempt("login", "192.0.2.10");
        assertTrue(limiter.isBlocked("login", "192.0.2.10"));
    }

    @Test
    void orderPolicyBlocksOnTenthOrderWithinOneMinute() {
        // 下单按账号限流：窗口 60s、阈值 10、封禁 60s。钉住「order」动作参数，
        // 防止有人把它混同登录（10/60/600）改错成误伤正常多店下单。
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        LoginRateLimiter limiter = new LoginRateLimiter(provider(redis));
        for (int i = 0; i < 10; i++) limiter.recordAttempt("order", "u1");
        assertTrue(limiter.isBlocked("order", "u1"));
        assertEquals(429, org.junit.jupiter.api.Assertions.assertThrows(com.example.takeout.common.BizException.class,
                () -> limiter.recordAttempt("order", "u1")).getCode());
    }

    @Test
    void loginResetCannotDeleteSharedCounterOrBlockMarker() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);

        new LoginRateLimiter(provider(redis)).reset("login", "1.1.1.1");

        verify(redis, never()).delete(anyString());
    }

    @Test
    void clientIpIgnoresRawForwardingHeader() {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getHeader("X-Forwarded-For")).thenReturn("1.1.1.1, 2.2.2.2");
        when(request.getRemoteAddr()).thenReturn("192.0.2.10");

        assertEquals("192.0.2.10", LoginRateLimiter.clientIp(request));
    }

    @Test
    void clientIpFallsBackToRemoteAddress() {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getRemoteAddr()).thenReturn("3.3.3.3");

        assertEquals("3.3.3.3", LoginRateLimiter.clientIp(request));
    }
}
