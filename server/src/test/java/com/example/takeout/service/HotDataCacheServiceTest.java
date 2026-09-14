package com.example.takeout.service;

import com.example.takeout.model.Category;
import com.fasterxml.jackson.core.type.TypeReference;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 热点缓存服务单测：重点覆盖缓存穿透、击穿、雪崩三类防护与 Redis 故障降级。
 */
class HotDataCacheServiceTest {

    private StringRedisTemplate redis;
    private ValueOperations<String, String> valueOps;
    private HotDataCacheService cache;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() throws Exception {
        redis = mock(StringRedisTemplate.class);
        valueOps = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(valueOps);

        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);

        cache = new HotDataCacheService(provider, new com.fasterxml.jackson.databind.ObjectMapper());
        ReflectionTestUtils.setField(cache, "enabled", true);
        ReflectionTestUtils.setField(cache, "keyPrefix", "takeout:");
        ReflectionTestUtils.setField(cache, "ttlSeconds", 300L);
        ReflectionTestUtils.setField(cache, "jitterSeconds", 120L);
        ReflectionTestUtils.setField(cache, "nullTtlSeconds", 60L);
        ReflectionTestUtils.setField(cache, "rebuildLockMs", 3000L);
        ReflectionTestUtils.setField(cache, "rebuildWaitMs", 0L);
    }

    private static final TypeReference<List<Category>> CATEGORY_LIST = new TypeReference<>() {
    };

    private List<Category> oneCategory() {
        return List.of(new Category(1, "美食", "", "#FF6B35", "PLATFORM", 0, 1, 1));
    }

    /** 命中缓存时不应回源数据库。 */
    @Test
    void returnsCachedValueWithoutHittingLoader() throws Exception {
        String json = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(oneCategory());
        when(valueOps.get("takeout:categories")).thenReturn(json);

        AtomicInteger loads = new AtomicInteger();
        List<Category> result = cache.get("categories", CATEGORY_LIST, () -> {
            loads.incrementAndGet();
            return oneCategory();
        });

        assertEquals(1, result.size());
        assertEquals(0, loads.get(), "命中缓存不应回源");
    }

    /**
     * 缓存穿透防护：数据不存在时写入空值占位，后续相同请求不再查库。
     */
    @Test
    void cachesNullResultToPreventPenetration() {
        when(valueOps.get(anyString())).thenReturn(null);
        when(valueOps.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(true);

        AtomicInteger loads = new AtomicInteger();
        Category first = cache.get("store:999", new TypeReference<Category>() {
        }, () -> {
            loads.incrementAndGet();
            return null;
        });
        assertNull(first);
        assertEquals(1, loads.get());

        // 占位已写入：验证写的是空值标记且 TTL 为短 TTL
        verify(valueOps).set(org.mockito.ArgumentMatchers.eq("takeout:store:999"),
                org.mockito.ArgumentMatchers.eq("\u0000NULL\u0000"),
                org.mockito.ArgumentMatchers.eq(Duration.ofSeconds(60)));

        // 第二次读取命中占位，数据库不再被访问（第二次不存在记录也算穿透成功）
        when(valueOps.get("takeout:store:999")).thenReturn("\u0000NULL\u0000");
        Category second = cache.get("store:999", new TypeReference<Category>() {
        }, () -> {
            loads.incrementAndGet();
            return null;
        });
        assertNull(second);
        assertEquals(1, loads.get(), "命中空值占位不应再次查库");
    }

    /**
     * 缓存雪崩防护：写入 TTL 必须带随机抖动，且落在 [base, base+jitter) 区间内。
     */
    @Test
    void appliesJitteredTtlToSpreadExpiry() throws Exception {
        when(valueOps.get(anyString())).thenReturn(null);
        when(valueOps.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(true);

        java.util.List<Long> ttls = new java.util.ArrayList<>();
        for (int i = 0; i < 20; i++) {
            cache.get("categories", CATEGORY_LIST, this::oneCategory);
        }
        // 捕获所有写入的 TTL
        org.mockito.ArgumentCaptor<Duration> captor = org.mockito.ArgumentCaptor.forClass(Duration.class);
        verify(valueOps, times(20)).set(anyString(), anyString(), captor.capture());
        for (Duration d : captor.getAllValues()) {
            ttls.add(d.getSeconds());
        }

        long min = ttls.stream().mapToLong(Long::longValue).min().orElseThrow();
        long max = ttls.stream().mapToLong(Long::longValue).max().orElseThrow();
        assertTrue(min >= 300, "TTL 不得低于基础值，实际 " + min);
        assertTrue(max < 300 + 120, "TTL 不得超过基础值+抖动上限，实际 " + max);
        assertTrue(max > min, "TTL 应有随机抖动以打散过期时刻，实际 min=" + min + " max=" + max);
    }

    /**
     * 缓存击穿防护：未抢到锁时等待回填结果，且不重复查库。
     */
    @Test
    void waitsForRebuildWhenLockNotAcquired() throws Exception {
        String json = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(oneCategory());
        // 第一次读未命中，之后等待期间能读到别人回填的值
        when(valueOps.get("takeout:categories")).thenReturn(null, json);
        // 抢锁失败 + 锁被他人持有
        when(valueOps.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(false);
        ReflectionTestUtils.setField(cache, "rebuildWaitMs", 500L);

        AtomicInteger loads = new AtomicInteger();
        List<Category> result = cache.get("categories", CATEGORY_LIST, () -> {
            loads.incrementAndGet();
            return oneCategory();
        });

        assertEquals(1, result.size(), "应复用他人回填的结果");
        assertEquals(0, loads.get(), "未抢到锁时不应自己回源数据库");
    }

    /** 回源抛异常时不得缓存错误结果。 */
    @Test
    void doesNotCacheWhenLoaderThrows() {
        when(valueOps.get(anyString())).thenReturn(null);
        when(valueOps.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(true);

        try {
            cache.get("categories", CATEGORY_LIST, () -> {
                throw new IllegalStateException("db down");
            });
        } catch (IllegalStateException expected) {
            // 异常按原样上抛
        }

        verify(valueOps, never()).set(anyString(), anyString(), any(Duration.class));
    }

    /**
     * Redis 不可用时的降级：全部读写异常都必须被吞掉并回源数据库。
     */
    @Test
    void degradesToDatabaseWhenRedisFails() {
        when(valueOps.get(anyString())).thenThrow(new org.springframework.data.redis.RedisConnectionFailureException("down"));
        when(redis.delete(anyString())).thenThrow(new org.springframework.data.redis.RedisConnectionFailureException("down"));

        List<Category> result = cache.get("categories", CATEGORY_LIST, this::oneCategory);
        assertEquals(1, result.size(), "Redis 故障时必须回源数据库而不是报错");
    }

    /** 失效接口在 Redis 故障时也不得抛异常影响主流程。 */
    @Test
    void evictIsSafeWhenRedisFails() {
        when(redis.delete(anyString())).thenThrow(new org.springframework.data.redis.RedisConnectionFailureException("down"));
        cache.evict("categories");
        cache.evict();
    }
}
