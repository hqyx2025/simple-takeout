package com.example.takeout.security;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Accepted restart side effects; these assertions deliberately do not claim a targeted local reset. */
class Round4RecoveryBoundaryTest {
    private final Map<String, Integer> actions = Map.of("upload", 30, "order", 10, "payment-password", 5, "register", 5, "email-code", 5);
    private LoginRateLimiter limiter(StringRedisTemplate redis) {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis); return new LoginRateLimiter(provider);
    }
    @Test void replacingTheProcessLosesAllFiveLocalOnlyActionWindows() {
        var old = limiter(null); var restarted = limiter(null);
        actions.forEach((action, limit) -> {
            for (int i = 0; i < limit; i++) old.recordAttempt(action, "local-only-test");
            assertTrue(old.isBlocked(action, "local-only-test"));
            assertFalse(restarted.isBlocked(action, "local-only-test"));
            assertDoesNotThrow(() -> restarted.recordAttempt(action, "local-only-test"));
        });
        System.out.println("[RT-22 accepted] restart loses local-only upload/order/payment-password/register/email-code windows=5");
    }
    @Test @EnabledIfEnvironmentVariable(named = "TAKEOUT_TEST_REDIS_PORT", matches = "\\d+")
    void existingRedisBudgetsForOtherActionsSurviveTheProcessReplacement() {
        var connection = new LettuceConnectionFactory("127.0.0.1", Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        connection.afterPropertiesSet(); connection.start(); var redis = new StringRedisTemplate(connection);
        String identity = "round4-recovery-" + UUID.randomUUID();
        try {
            var old = limiter(redis); var restarted = limiter(redis);
            actions.forEach((action, limit) -> {
                for (int i = 0; i < limit; i++) old.recordAttempt(action, identity);
                assertTrue(restarted.isBlocked(action, identity));
            });
            System.out.println("[RT-22 accepted] existing Redis blocks after local replacement: preserved-actions=5");
        } finally {
            actions.keySet().forEach(action -> redis.delete(List.of("takeout:rl:" + action + ":" + identity,
                    "takeout:rl:" + action + ":" + identity + ":blocked")));
            connection.destroy();
        }
    }
}
