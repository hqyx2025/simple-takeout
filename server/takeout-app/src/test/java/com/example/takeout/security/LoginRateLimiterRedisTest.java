package com.example.takeout.security;

import com.example.takeout.common.BizException;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_TEST_REDIS_PORT", matches = "\\d+")
class LoginRateLimiterRedisTest {
    private LettuceConnectionFactory connection;
    private StringRedisTemplate redis;
    private final String identity = "test-" + UUID.randomUUID();

    @BeforeEach void connect() {
        connection = new LettuceConnectionFactory("127.0.0.1", Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        connection.afterPropertiesSet();
        connection.start();
        redis = new StringRedisTemplate(connection);
    }

    @SuppressWarnings("unchecked") private LoginRateLimiter instance() {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);
        return new LoginRateLimiter(provider);
    }

    @AfterEach void clean() {
        try { for (String action : List.of("login", "payment-password")) instance().reset(action, identity); }
        finally { connection.destroy(); }
    }

    @Test void independentInstancesCannotOverspendOneSharedBudget() throws Exception {
        AtomicInteger admitted = new AtomicInteger();
        CountDownLatch start = new CountDownLatch(1);
        try (var pool = Executors.newFixedThreadPool(16)) {
            List<Future<?>> futures = new ArrayList<>();
            for (int i = 0; i < 64; i++) {
                LoginRateLimiter limiter = instance();
                futures.add(pool.submit(() -> {
                    try {
                        assertTrue(start.await(5, TimeUnit.SECONDS));
                        limiter.recordAttempt("payment-password", identity);
                        admitted.incrementAndGet();
                    } catch (BizException e) { assertEquals(429, e.getCode()); }
                    catch (InterruptedException e) { throw new RuntimeException(e); }
                }));
            }
            start.countDown();
            for (var future : futures) future.get(10, TimeUnit.SECONDS);
        } finally { start.countDown(); }
        assertEquals(5, admitted.get());
        assertTrue(instance().isBlocked("payment-password", identity));
        Long ttl = redis.getExpire("takeout:rl:payment-password:" + identity + ":blocked");
        assertNotNull(ttl);
        assertTrue(ttl > 0 && ttl <= 600);
    }

    @Test void laterAttemptsDoNotExtendTheFixedWindowAndLoginResetCannotClearIt() {
        instance().recordAttempt("login", identity);
        String key = "takeout:rl:login:" + identity;
        redis.expire(key, Duration.ofSeconds(7));
        instance().recordAttempt("login", identity);
        assertTrue(redis.getExpire(key) <= 7);
        assertEquals("2", redis.opsForValue().get(key));
        instance().reset("login", identity);
        assertEquals("2", redis.opsForValue().get(key));
        assertFalse(instance().isBlocked("login", identity));
        for (int i = 0; i < 8; i++) instance().recordAttempt("login", identity);
        instance().reset("login", identity);
        assertTrue(instance().isBlocked("login", identity));
    }

    @Test void accountTotalHasThirtyAdmissionsAndOnlySixtySecondBlock() {
        String key = "takeout:rl:login-account-total:" + identity;
        try {
            for (int i = 0; i < 30; i++) instance().recordAttempt("login-account-total", identity);
            assertTrue(instance().isBlocked("login-account-total", identity));
            Long ttl = redis.getExpire(key + ":blocked");
            assertNotNull(ttl); assertTrue(ttl > 0 && ttl <= 60);
            assertFalse(instance().isBlocked("login-account-fail", identity));
            System.out.println("[RT-23/Redis] account-total admissions=30 block-TTL-seconds=" + ttl + " failure-block=false");
        } finally { redis.delete(java.util.List.of(key, key + ":blocked")); }
    }
}
