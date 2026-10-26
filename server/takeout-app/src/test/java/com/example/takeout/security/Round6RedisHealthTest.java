package com.example.takeout.security;

import com.example.takeout.common.BizException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.RedisConnectionFailureException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round6RedisHealthTest {
    private LoginRateLimiter limiter(StringRedisTemplate redis) {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis); return new LoginRateLimiter(provider);
    }

    @Test void slowSuccessfulReadStopsRepeatedRoundTripsAndLocalFailureLimitStillHolds() throws Exception {
        var calls = new AtomicInteger(); var redis = mock(StringRedisTemplate.class);
        when(redis.hasKey(anyString())).thenAnswer(call -> {
            calls.incrementAndGet(); Thread.sleep(500); return false;
        });
        var limiter = limiter(redis);
        assertFalse(limiter.isBlocked("login", "192.0.2.1"));
        for (int i = 0; i < 3; i++) assertFalse(limiter.isBlocked("login-total", "192.0.2." + (i + 2)));
        System.out.println("[RT-29/health] slow-read Redis calls=" + calls.get());
        assertEquals(1, calls.get());
        for (int i = 0; i < 10; i++) limiter.recordAttempt("login", "192.0.2.1");
        assertTrue(limiter.isBlocked("login", "192.0.2.1"));
        assertEquals(429, assertThrows(BizException.class, () -> limiter.recordAttempt("login", "192.0.2.1")).getCode());
        verify(redis, never()).execute(any(RedisScript.class), anyList(), any(Object[].class));
        System.out.println("[RT-29/health] fallback failures=10 next=429 local-block-preserved=true");
    }

    @Test void connectionFailureDoesNotKeepRetryingAndOverflowProtectionStillHolds() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.hasKey(anyString())).thenThrow(new RedisConnectionFailureException("test unavailable"));
        var limiter = limiter(redis);
        assertFalse(limiter.isBlocked("login", "192.0.2.1"));
        for (int i = 0; i < 3; i++) assertFalse(limiter.isBlocked("login-total", "192.0.2." + (i + 2)));
        verify(redis, times(1)).hasKey(anyString());
        for (int i = 0; i < 10_000; i++) limiter.recordAttempt("login-account-total", "fill-" + i);
        for (int i = 0; i < 10; i++) limiter.recordAttempt("login-account-fail", "u7");
        assertTrue(limiter.isBlocked("login-account-fail", "u7"));
        assertEquals(429, assertThrows(BizException.class,
                () -> limiter.recordAttempt("login-account-fail", "u7")).getCode());
        verify(redis, never()).execute(any(RedisScript.class), anyList(), any(Object[].class));
        System.out.println("[RT-29/health] exception Redis calls=1 full-local-table=10000 overflow-next=429");
    }

    @Test void slowRedisDenialRemainsAuthoritativeAndDoesNotDisableOtherActions() throws Exception {
        var redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(RedisScript.class), anyList(), any(Object[].class))).thenAnswer(call -> {
            Thread.sleep(500); return 0L;
        });
        var limiter = limiter(redis);
        assertEquals(429, assertThrows(BizException.class,
                () -> limiter.recordAttempt("login-total", "192.0.2.1")).getCode());
        assertTrue(limiter.isBlocked("login-total", "192.0.2.1"), "a received Redis denial must survive short-circuiting");
        assertFalse(limiter.isBlocked("login", "192.0.2.2"));
        verify(redis, never()).hasKey(anyString());
        // Login-only degradation must not turn off Redis's payment-password decision.
        assertEquals(429, assertThrows(BizException.class,
                () -> limiter.recordAttempt("payment-password", "u7")).getCode());
        verify(redis, times(2)).execute(any(RedisScript.class), anyList(), any(Object[].class));
        System.out.println("[RT-29/health] slow-Redis-login-denial=429 non-login-Redis-denial=429");
    }

    @Test void knownRedisBlockSurvivesShortCircuiting() throws Exception {
        var redis = mock(StringRedisTemplate.class);
        when(redis.hasKey(anyString())).thenAnswer(call -> { Thread.sleep(500); return true; });
        var limiter = limiter(redis);
        assertTrue(limiter.isBlocked("login-account-fail", "u7"));
        assertTrue(limiter.isBlocked("login-account-fail", "u7"));
        verify(redis, times(1)).hasKey(anyString());
        System.out.println("[RT-29/health] observed-Redis-block-retained=true Redis-calls=1");
    }

    @Test void recoveryAllowsOneProbeAndRetainsExistingLocalBlocks() throws Exception {
        var redis = mock(StringRedisTemplate.class);
        var calls = new AtomicInteger(); var slowProbeEntered = new java.util.concurrent.CountDownLatch(1);
        var releaseProbe = new java.util.concurrent.CountDownLatch(1);
        when(redis.hasKey(anyString())).thenAnswer(call -> {
            int number = calls.incrementAndGet();
            if (number == 1) throw new RedisConnectionFailureException("test unavailable");
            if (number == 2) {
                slowProbeEntered.countDown();
                assertTrue(releaseProbe.await(3, java.util.concurrent.TimeUnit.SECONDS));
                Thread.sleep(500); // A slow, successful probe must reopen the cooldown.
            }
            return false;
        });
        var limiter = limiter(redis);
        assertFalse(limiter.isBlocked("login", "initial"));
        for (int i = 0; i < 10; i++) limiter.recordAttempt("login-account-fail", "u7");
        assertTrue(limiter.isBlocked("login-account-fail", "u7"));
        verify(redis, never()).execute(any(RedisScript.class), anyList(), any(Object[].class));
        Thread.sleep(5100);
        try (var pool = java.util.concurrent.Executors.newSingleThreadExecutor()) {
            var probe = pool.submit(() -> limiter.isBlocked("login-total", "probe"));
            try {
                assertTrue(slowProbeEntered.await(3, java.util.concurrent.TimeUnit.SECONDS));
                for (int i = 0; i < 32; i++) assertFalse(limiter.isBlocked("login-total", "parallel-" + i));
                assertEquals(2, calls.get());
            } finally { releaseProbe.countDown(); }
            assertFalse(probe.get(3, java.util.concurrent.TimeUnit.SECONDS));
        }
        assertFalse(limiter.isBlocked("login-total", "still-cooling"));
        assertEquals(2, calls.get());
        Thread.sleep(5100);
        assertFalse(limiter.isBlocked("login-total", "fast-recovery"));
        assertFalse(limiter.isBlocked("login-total", "distributed-again"));
        assertEquals(4, calls.get());
        assertTrue(limiter.isBlocked("login-account-fail", "u7"));
        System.out.println("[RT-29/recovery] single-probe=true slow-probe-reopens=true fast-probe-restores=true local-block-retained=true");
    }
}
