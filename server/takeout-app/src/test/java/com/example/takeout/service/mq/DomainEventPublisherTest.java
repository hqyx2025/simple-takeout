package com.example.takeout.service.mq;

import com.example.takeout.dao.OutboxEventDao;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StreamOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 领域事件发布器单测。
 *
 * 序列化/Redis 故障降级；数据库异常必须传播并回滚业务事务，避免死锁后误报成功。
 * 同时保证事件确实被记录，
 * 以及 Redis 缺失时投递返回失败（交给中继重试）而不是误报成功。
 */
class DomainEventPublisherTest {

    @org.junit.jupiter.api.AfterEach
    void clearTrace() { com.example.takeout.common.TraceContext.clear(); }

    @Test
    void persistsOriginatingTraceWithoutMutatingBusinessPayload() throws Exception {
        com.example.takeout.common.TraceContext.bind("original-request");
        var payload = new java.util.LinkedHashMap<String,Object>(Map.of("userId", 1L));
        publisher.publish(DomainEventPublisher.ORDER_CREATED, 42L, payload);
        var json = org.mockito.ArgumentCaptor.forClass(String.class);
        verify(outboxDao).insert(anyString(), org.mockito.ArgumentMatchers.eq(42L), json.capture(), anyString());
        assertTrue(new ObjectMapper().readTree(json.getValue()).path("_traceId").asText().equals("original-request"));
        org.junit.jupiter.api.Assertions.assertEquals(Map.of("userId", 1L), payload);
    }

    @Test
    void retryDeliversOriginalTraceAndRestoresSchedulerMdcEvenOnFailure() {
        com.example.takeout.common.TraceContext.bind("scheduler");
        when(streamOps.add(any())).thenAnswer(invocation -> {
            org.junit.jupiter.api.Assertions.assertEquals("original-request", com.example.takeout.common.TraceContext.current());
            org.springframework.data.redis.connection.stream.MapRecord<?,?,?> record = invocation.getArgument(0);
            org.junit.jupiter.api.Assertions.assertEquals("original-request", record.getValue().get("traceId"));
            throw new IllegalStateException("injected Redis outage");
        });
        assertFalse(publisher.deliver(1, DomainEventPublisher.ORDER_CREATED, 42, "{\"_traceId\":\"original-request\"}"));
        org.junit.jupiter.api.Assertions.assertEquals("scheduler", com.example.takeout.common.TraceContext.current());
    }

    private OutboxEventDao outboxDao;
    private StringRedisTemplate redis;
    private StreamOperations<String, Object, Object> streamOps;
    private DomainEventPublisher publisher;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() {
        outboxDao = mock(OutboxEventDao.class);
        redis = mock(StringRedisTemplate.class);
        streamOps = mock(StreamOperations.class);
        when(redis.opsForStream()).thenReturn(streamOps);
        when(redis.hasKey(anyString())).thenReturn(true);

        @SuppressWarnings("unchecked")
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);

        publisher = new DomainEventPublisher(outboxDao, provider, new ObjectMapper());
        ReflectionTestUtils.setField(publisher, "enabled", true);
        ReflectionTestUtils.setField(publisher, "streamMaxLen", 1000L);
    }

    /** 正常发布：事件必须落到 Outbox 表（与业务同事务）。 */
    @Test
    void recordsEventToOutbox() {
        publisher.publish(DomainEventPublisher.ORDER_CREATED, 42L, Map.of("userId", 1L));

        verify(outboxDao, times(1)).insert(
                org.mockito.ArgumentMatchers.eq(DomainEventPublisher.ORDER_CREATED),
                org.mockito.ArgumentMatchers.eq(42L),
                anyString(), anyString());
    }

    /** 关闭开关后不应写任何事件。 */
    @Test
    void doesNothingWhenDisabled() {
        ReflectionTestUtils.setField(publisher, "enabled", false);

        publisher.publish(DomainEventPublisher.ORDER_CREATED, 42L, Map.of("userId", 1L));

        verify(outboxDao, never()).insert(anyString(), anyLong(), anyString(), anyString());
    }

    /** Durable cross-service events must roll back with the business when persistence fails. */
    @Test
    void propagatesOutboxFailureToPreserveAtomicity() {
        when(outboxDao.insert(anyString(), anyLong(), anyString(), anyString()))
                .thenThrow(new RuntimeException("db down"));

        org.junit.jupiter.api.Assertions.assertThrows(IllegalStateException.class, () ->
                publisher.publish(DomainEventPublisher.ORDER_CREATED, 42L, Map.of("userId", 1L)));
    }

    @Test
    void propagatesDatabaseDeadlockSoBusinessTransactionCannotReportSuccess() {
        var failure = new org.springframework.dao.CannotAcquireLockException("deadlock");
        when(outboxDao.insert(anyString(), anyLong(), anyString(), anyString())).thenThrow(failure);

        org.junit.jupiter.api.Assertions.assertSame(failure,
                org.junit.jupiter.api.Assertions.assertThrows(org.springframework.dao.CannotAcquireLockException.class,
                        () -> publisher.publish(DomainEventPublisher.ORDER_CREATED, 42L, Map.of())));
    }

    /** An event that cannot be serialized must not disappear behind business success. */
    @Test
    void propagatesSerializationFailure() {
        Object selfReferencing = new Object() {
            @SuppressWarnings("unused")
            public Object getSelf() {
                throw new IllegalStateException("cannot serialize");
            }
        };

        org.junit.jupiter.api.Assertions.assertThrows(IllegalStateException.class, () ->
                publisher.publish(DomainEventPublisher.ORDER_CREATED, 42L, Map.of("bad", selfReferencing)));
    }

    /** Redis 可用时投递成功。 */
    @Test
    void deliversToStreamWhenRedisAvailable() {
        boolean ok = publisher.deliver(1L, DomainEventPublisher.ORDER_CREATED, 42L, "{}");

        assertTrue(ok, "Redis 可用时应投递成功");
        verify(streamOps, times(1)).add(any());
    }

    /** Redis 不可用时投递必须返回 false（交由中继重试），不能误报成功导致事件丢失。 */
    @Test
    void returnsFalseWhenRedisUnavailable() {
        @SuppressWarnings("unchecked")
        ObjectProvider<StringRedisTemplate> emptyProvider = mock(ObjectProvider.class);
        when(emptyProvider.getIfAvailable()).thenReturn(null);
        DomainEventPublisher noRedis = new DomainEventPublisher(outboxDao, emptyProvider, new ObjectMapper());
        ReflectionTestUtils.setField(noRedis, "enabled", true);

        assertFalse(noRedis.deliver(1L, DomainEventPublisher.ORDER_CREATED, 42L, "{}"));
    }

    /** Redis 抛异常时投递返回 false，且不影响调用方。 */
    @Test
    void returnsFalseWhenRedisThrows() {
        when(streamOps.add(any())).thenThrow(new RuntimeException("connection refused"));

        boolean ok = assertDoesNotThrow(() ->
                publisher.deliver(1L, DomainEventPublisher.ORDER_CREATED, 42L, "{}"));

        assertFalse(ok, "投递异常应返回 false 以触发重试");
    }
}
