package com.example.takeout.security;

import com.example.takeout.common.BizException;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.connection.RedisStandaloneConfiguration;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.jdbc.core.JdbcTemplate;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_TEST_REDIS_PORT", matches = "\\d+")
class ClaimTrafficRedisTest {
    private static final String PREFIX = "takeout:claim:{traffic}:";
    private LettuceConnectionFactory connection;
    private StringRedisTemplate redis;
    @BeforeEach void start() {
        var config = new RedisStandaloneConfiguration("127.0.0.1", Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        config.setDatabase(13);
        connection = new LettuceConnectionFactory(config);
        connection.afterPropertiesSet(); connection.start();
        redis = new StringRedisTemplate(connection);
        redis.delete(List.of(PREFIX + "rate:COUPON", PREFIX + "rate:RIDER"));
    }
    @AfterEach void stop() { if (connection != null) connection.destroy(); }

    private ClaimTrafficGuard guard(ClaimTrafficSettings settings) {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);
        return new ClaimTrafficGuard(provider, mock(JdbcTemplate.class), settings);
    }
    private void coupon(ClaimTrafficGuard guard) {
        try (var lease = guard.enter(ClaimTrafficGuard.Action.COUPON)) { lease.admit(null); lease.succeeded(true); }
    }

    @Test void perSecondBudgetIsSharedByTwoInstances() {
        var first = guard(ClaimTrafficGuardTest.settings(4, 5, 3));
        var second = guard(ClaimTrafficGuardTest.settings(4, 5, 3));
        coupon(first); coupon(second); coupon(first); coupon(second); coupon(first);
        assertEquals(429, assertThrows(BizException.class, () -> coupon(second)).getCode());
    }

    @Test void twoInstancesFilterSameOrderAndReleaseAfterRequestCompletes() {
        var first = guard(ClaimTrafficGuardTest.settings(4, 100, 3));
        var second = guard(ClaimTrafficGuardTest.settings(4, 100, 3));
        String order = UUID.randomUUID().toString();
        try (var held = first.enter(ClaimTrafficGuard.Action.RIDER)) {
            held.admit(order);
            try (var competing = second.enter(ClaimTrafficGuard.Action.RIDER)) {
                assertEquals(409, assertThrows(BizException.class, () -> competing.admit(order)).getCode());
            }
            try (var other = second.enter(ClaimTrafficGuard.Action.RIDER)) { other.admit(order + "-other"); }
        }
        try (var retry = second.enter(ClaimTrafficGuard.Action.RIDER)) { retry.admit(order); }
        assertFalse(redis.hasKey(PREFIX + "order:" + order));
    }

    @Test void thirtyTwoContendersOnlyAdmitOneRequestAcrossInstances() throws Exception {
        var first = guard(ClaimTrafficGuardTest.settings(4, 100, 3));
        var second = guard(ClaimTrafficGuardTest.settings(4, 100, 3));
        var attempted = new CountDownLatch(32); var start = new CountDownLatch(1);
        var accepted = new AtomicInteger(); String order = UUID.randomUUID().toString();
        try (var pool = Executors.newFixedThreadPool(32)) {
            var tasks = new ArrayList<Future<?>>();
            for (int i = 0; i < 32; i++) {
                var selected = i % 2 == 0 ? first : second;
                tasks.add(pool.submit(() -> {
                    assertTrue(start.await(5, TimeUnit.SECONDS));
                    boolean counted = false;
                    try (var lease = selected.enter(ClaimTrafficGuard.Action.RIDER)) {
                        lease.admit(order); accepted.incrementAndGet();
                        attempted.countDown(); counted = true;
                        assertTrue(attempted.await(5, TimeUnit.SECONDS));
                    } catch (BizException e) { assertTrue(e.getCode() == 409 || e.getCode() == 503); }
                    finally { if (!counted) attempted.countDown(); }
                    return null;
                }));
            }
            start.countDown();
            for (var task : tasks) task.get(10, TimeUnit.SECONDS);
        }
        assertEquals(1, accepted.get());
    }

    @Test void expiredOldOwnerCannotReleaseAnotherInstancesNewLease() {
        var first = guard(ClaimTrafficGuardTest.settings(4, 100, 3));
        var second = guard(ClaimTrafficGuardTest.settings(4, 100, 3));
        String order = UUID.randomUUID().toString(), key = PREFIX + "order:" + order;
        try (var old = first.enter(ClaimTrafficGuard.Action.RIDER)) {
            old.admit(order);
            assertTrue(redis.getExpire(key) > 0);
            redis.expire(key, Duration.ZERO);
            try (var replacement = second.enter(ClaimTrafficGuard.Action.RIDER)) {
                replacement.admit(order);
                String newOwner = redis.opsForValue().get(key);
                old.close();
                assertEquals(newOwner, redis.opsForValue().get(key));
            }
        }
        assertFalse(redis.hasKey(key));
    }

    @Test void redisFailureUsesBoundedLocalProtectionAndRestoresDistributedFiltering() {
        AtomicLong clock = new AtomicLong(1_000_000_000L);
        var failing = mock(StringRedisTemplate.class);
        when(failing.execute(any(RedisScript.class), anyList(), any(Object[].class)))
                .thenThrow(new org.springframework.data.redis.RedisConnectionFailureException("offline"));
        AtomicReference<StringRedisTemplate> current = new AtomicReference<>(failing);
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenAnswer(call -> current.get());
        var first = new ClaimTrafficGuard(provider, mock(JdbcTemplate.class), ClaimTrafficGuardTest.settings(2, 100, 3), clock::get);
        for (int i = 0; i < 5; i++) coupon(first);
        verify(failing, times(1)).execute(any(RedisScript.class), anyList(), any(Object[].class));
        current.set(redis); clock.addAndGet(Duration.ofSeconds(5).toNanos());
        var second = guard(ClaimTrafficGuardTest.settings(2, 100, 3));
        String order = UUID.randomUUID().toString();
        try (var held = first.enter(ClaimTrafficGuard.Action.RIDER)) {
            held.admit(order);
            try (var competing = second.enter(ClaimTrafficGuard.Action.RIDER)) {
                assertEquals(409, assertThrows(BizException.class, () -> competing.admit(order)).getCode());
            }
        }
    }
}
