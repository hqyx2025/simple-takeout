package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.*;
import org.springframework.test.util.ReflectionTestUtils;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round8CacheResourceTest {
    private static final TypeReference<String> TEXT = new TypeReference<>() {};
    private static class CacheFixture {
        final Map<String,String> values = new HashMap<>();
        final Set<String> locks = new HashSet<>();
        final HotDataCacheService cache;
        CacheFixture() {
            var redis = mock(StringRedisTemplate.class);
            ValueOperations<String,String> ops = mock(ValueOperations.class);
            when(redis.opsForValue()).thenReturn(ops);
            when(ops.get(anyString())).thenAnswer(call -> values.get(call.getArgument(0)));
            doAnswer(call -> { values.put(call.getArgument(0), call.getArgument(1)); return null; })
                    .when(ops).set(anyString(), anyString(), any(Duration.class));
            when(ops.setIfAbsent(anyString(), anyString(), any(Duration.class)))
                    .thenAnswer(call -> { locks.add(call.getArgument(0)); return true; });
            ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
            when(provider.getIfAvailable()).thenReturn(redis);
            cache = new HotDataCacheService(provider, new ObjectMapper());
            ReflectionTestUtils.setField(cache, "rebuildWaitMs", 0L);
        }
    }

    @Test void arbitraryCoordinatesAndRadiiCannotCreateMoreThan512ValueSlots() {
        var fixture = new CacheFixture();
        for (int i = 0; i < 2000; i++) {
            String key = "untrusted-query:" + i + ":" + (2 + i * 1e-10);
            String expected = "query-result-" + i;
            assertEquals(expected, fixture.cache.get(key, TEXT, () -> expected));
            assertEquals(expected, fixture.cache.get(key, TEXT, () -> { throw new AssertionError("same query must hit"); }));
        }
        System.out.println("[RT-34/slots] requests=2000 value-keys=" + fixture.values.size() + " distinct-lock-keys=" + fixture.locks.size());
        assertTrue(fixture.values.size() <= 512); assertTrue(fixture.locks.size() <= 512);
    }

    @Test void collisionsNeverReturnAnotherQueriesResponse() {
        var fixture = new CacheFixture(); var loads = new AtomicInteger();
        for (String key : List.of("stores:Aa", "stores:BB", "stores:Aa")) {
            assertEquals(key, fixture.cache.get(key, TEXT, () -> { loads.incrementAndGet(); return key; }));
        }
        // Aa / BB share a Java hash, so a bounded slot cache must distinguish their identities.
        System.out.println("[RT-34/collision] distinct-query-results-correct=true loads=" + loads.get());
    }

    @Test void oversizePayloadReturnsNormallyWithoutWritingRedis() {
        var fixture = new CacheFixture(); String huge = "中".repeat(70_000);
        assertEquals(huge, fixture.cache.get("stores:huge", TEXT, () -> huge));
        assertTrue(fixture.values.isEmpty());
        System.out.println("[RT-34/payload] oversize-response-returned=true cached-values=" + fixture.values.size());
    }

    @Test void everyCoordinateAwareBrowseRejectsOutOfRangePartialAndNonFinitePairs() {
        var cache = mock(HotDataCacheService.class);
        var service = new StoreService(mock(StoreDao.class), mock(GoodsDao.class), mock(GoodsSpecDao.class),
                mock(SeckillDao.class), new ObjectMapper(), cache, mock(EmployeeDao.class));
        int rejected = 0;
        for (Double[] pair : new Double[][]{{91.0, 114.0}, {30.0, 181.0}, {Double.NaN, 114.0},
                {30.0, Double.POSITIVE_INFINITY}, {30.0, null}, {null, 114.0}}) {
            var calls = List.<Runnable>of(() -> service.listStores(null, pair[0], pair[1]),
                    () -> service.recommendedStores(2, 10, pair[0], pair[1]),
                    () -> service.listSpecialGoods(10, pair[0], pair[1]),
                    () -> service.rankStores(10, pair[0], pair[1]),
                    () -> service.rankGoods(10, pair[0], pair[1]),
                    () -> service.listSeckills(10, pair[0], pair[1]));
            for (var call : calls) { assertEquals(400, assertThrows(BizException.class, call::run).getCode()); rejected++; }
        }
        verifyNoInteractions(cache);
        when(cache.get(any(), any(), any())).thenAnswer(call -> ((java.util.function.Supplier<?>) call.getArgument(2)).get());
        assertDoesNotThrow(() -> service.listStores(null, null, null));
        assertDoesNotThrow(() -> service.listStores(null, -90.0, 180.0));
        System.out.println("[RT-34/coordinates] rejected-before-cache=" + rejected + " absent-location=allowed boundary=allowed");
    }
}
