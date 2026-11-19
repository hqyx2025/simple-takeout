package com.example.takeout.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.charset.StandardCharsets;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_TEST_REDIS_PORT", matches = "\\d+")
class Round8CacheRedisTest {
    @Test void stockCatalogExpiresWithoutAnyPerOrderInvalidation() throws Exception {
        var factory = new LettuceConnectionFactory("127.0.0.1", Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        factory.afterPropertiesSet(); factory.start();
        var redis = new StringRedisTemplate(factory);
        String prefix = "stock-ttl:" + UUID.randomUUID() + ":";
        try {
            ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
            when(provider.getIfAvailable()).thenReturn(redis);
            var a = new HotDataCacheService(provider,new ObjectMapper());
            var b = new HotDataCacheService(provider,new ObjectMapper());
            for (var cache:List.of(a,b)) ReflectionTestUtils.setField(cache,"keyPrefix",prefix);
            var stock=new java.util.concurrent.atomic.AtomicInteger(10);
            var type=new TypeReference<Integer>() {};
            String key=HotDataCacheService.Keys.storeGoods(1);
            assertEquals(10,a.get(key,type,stock::get));
            stock.set(8);
            assertEquals(10,b.get(key,type,stock::get));
            Thread.sleep(1200);
            assertEquals(8,b.get(key,type,stock::get),"A normal stock read must refresh within one second without cache deletion");
        } finally {
            Set<String> keys=redis.keys(prefix+"*");if(keys!=null&&!keys.isEmpty())redis.delete(keys);
            factory.destroy();
        }
    }

    @Test void sharedPhysicalSlotsRemainBoundedAndCacheFlushPreservesSecurityKeys() {
        var factory = new LettuceConnectionFactory("127.0.0.1", Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        factory.afterPropertiesSet(); factory.start();
        var redis = new StringRedisTemplate(factory);
        String prefix = "round8:" + UUID.randomUUID() + ":";
        try {
            ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
            when(provider.getIfAvailable()).thenReturn(redis);
            var a = new HotDataCacheService(provider, new ObjectMapper());
            var b = new HotDataCacheService(provider, new ObjectMapper());
            for (var cache : List.of(a, b)) {
                ReflectionTestUtils.setField(cache, "keyPrefix", prefix);
                ReflectionTestUtils.setField(cache, "rebuildWaitMs", 0L);
            }
            String securityKey = prefix + "rl:login:sentinel:blocked";
            redis.opsForValue().set(securityKey, "1");
            for (int i = 0; i < 2000; i++) {
                String key = "untrusted-query:" + i + ":" + (2 + i * 1e-10);
                String value = "result-" + i + "中".repeat(512);
                assertEquals(value, (i % 2 == 0 ? a : b).get(key, new TypeReference<String>() {}, () -> value));
            }
            Set<String> keys = redis.keys(prefix + "hot:v4:*"); assertNotNull(keys); assertFalse(keys.isEmpty());
            assertTrue(keys.size() <= 512, "completed loads must release their lock keys");
            long bytes = keys.stream().map(redis.opsForValue()::get).filter(Objects::nonNull)
                    .mapToLong(value -> value.getBytes(StandardCharsets.UTF_8).length).sum();
            assertTrue(bytes <= 512L * 65536);
            a.evictAll();
            assertEquals("1", redis.opsForValue().get(securityKey));
            assertTrue(redis.keys(prefix + "hot:v4:*").isEmpty());
            System.out.println("[RT-34/Redis] instances=2 queries=2000 data-keys=" + keys.size()
                    + " encoded-bytes=" + bytes + " cache-flush-keeps-security-key=true");
        } finally {
            Set<String> keys = redis.keys(prefix + "*"); if (keys != null && !keys.isEmpty()) redis.delete(keys);
            factory.destroy();
        }
    }
}
