package com.example.takeout.security;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.RedisConnectionFailureException;
import org.springframework.data.redis.core.StringRedisTemplate;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round7LegacyLoginActionTest {
    private LoginRateLimiter limiter(StringRedisTemplate redis) {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);
        return new LoginRateLimiter(provider);
    }

    @Test void obsoleteActionDoesNotOpenTheLiveLoginCircuit() {
        var redis = mock(StringRedisTemplate.class);
        when(redis.hasKey("takeout:rl:login-account:legacy:blocked"))
                .thenThrow(new RedisConnectionFailureException("obsolete caller test"));
        when(redis.hasKey("takeout:rl:login:192.0.2.207:blocked")).thenReturn(true);
        var limiter = limiter(redis);
        assertFalse(limiter.isBlocked("login-account", "legacy"));
        boolean blocked = limiter.isBlocked("login", "192.0.2.207");
        System.out.println("[RT-33] obsolete-action-error live-login-block-visible=" + blocked);
        assertTrue(blocked);
        verify(redis).hasKey("takeout:rl:login:192.0.2.207:blocked");
    }

    @Test void resetsStillCannotDeleteLegacyOrLiveLoginKeys() {
        var redis = mock(StringRedisTemplate.class);
        var limiter = limiter(redis);
        for (String action : java.util.List.of("login-account", "login", "login-total",
                "login-account-fail", "login-account-total")) {
            limiter.reset(action, "u7");
        }
        verifyNoInteractions(redis);
        System.out.println("[RT-33] protected-reset-actions=5 Redis-delete-calls=0");
    }
}
