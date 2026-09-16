package com.example.takeout.security;

import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 登录限流的口径测试：阈值触发封禁、窗口起点只设一次、Redis 不可用时放行。
 */
class LoginRateLimiterTest {

    @SuppressWarnings("unchecked")
    private ObjectProvider<StringRedisTemplate> provider(StringRedisTemplate redis) {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);
        return provider;
    }

    @Test
    void allowsEverythingWhenRedisUnavailable() {
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
    void startsWindowOnlyOnFirstAttempt() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> ops = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(ops);
        when(ops.increment("takeout:rl:login:1.1.1.1")).thenReturn(1L);

        new LoginRateLimiter(provider(redis)).recordAttempt("login", "1.1.1.1");

        verify(redis).expire("takeout:rl:login:1.1.1.1", Duration.ofSeconds(60));
        verify(ops, never()).set(any(), any(), any(Duration.class));
    }

    @Test
    void blocksIpWhenAttemptsReachLimit() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> ops = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(ops);
        when(ops.increment("takeout:rl:login:1.1.1.1")).thenReturn(10L);

        new LoginRateLimiter(provider(redis)).recordAttempt("login", "1.1.1.1");

        verify(ops).set(eq("takeout:rl:login:1.1.1.1:blocked"), eq("1"), eq(Duration.ofSeconds(600)));
        verify(redis).delete("takeout:rl:login:1.1.1.1");
    }

    @Test
    void orderPolicyBlocksOnTenthOrderWithinOneMinute() {
        // 下单按账号限流：窗口 60s、阈值 10、封禁 60s。钉住「order」动作参数，
        // 防止有人把它混同登录（10/60/600）改错成误伤正常多店下单。
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> ops = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(ops);
        when(ops.increment("takeout:rl:order:u1")).thenReturn(10L);

        new LoginRateLimiter(provider(redis)).recordAttempt("order", "u1");

        verify(ops).set(eq("takeout:rl:order:u1:blocked"), eq("1"), eq(Duration.ofSeconds(60)));
        verify(redis).delete("takeout:rl:order:u1");
    }

    @Test
    void resetClearsCounterAndBlockMarker() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);

        new LoginRateLimiter(provider(redis)).reset("login", "1.1.1.1");

        verify(redis).delete("takeout:rl:login:1.1.1.1");
        verify(redis).delete("takeout:rl:login:1.1.1.1:blocked");
    }

    @Test
    void clientIpPrefersForwardedHeader() {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getHeader("X-Forwarded-For")).thenReturn("1.1.1.1, 2.2.2.2");

        assertEquals("1.1.1.1", LoginRateLimiter.clientIp(request));
    }

    @Test
    void clientIpFallsBackToRemoteAddress() {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getRemoteAddr()).thenReturn("3.3.3.3");

        assertEquals("3.3.3.3", LoginRateLimiter.clientIp(request));
    }
}