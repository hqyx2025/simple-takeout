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
 * 重点验证「事件机制绝不能拖垮主业务」：Outbox 写入失败、序列化失败、
 * Redis 不可用等异常都不得向上抛出；同时保证事件确实被记录，
 * 以及 Redis 缺失时投递返回失败（交给中继重试）而不是误报成功。
 */
class DomainEventPublisherTest {

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

    /** Outbox 落库失败必须被吞掉：不能因为记不下事件就让下单失败。 */
    @Test
    void swallowsOutboxFailureToProtectBusiness() {
        when(outboxDao.insert(anyString(), anyLong(), anyString(), anyString()))
                .thenThrow(new RuntimeException("db down"));

        assertDoesNotThrow(() ->
                publisher.publish(DomainEventPublisher.ORDER_CREATED, 42L, Map.of("userId", 1L)));
    }

    /** payload 无法序列化时也不得抛异常。 */
    @Test
    void swallowsSerializationFailure() {
        Object selfReferencing = new Object() {
            @SuppressWarnings("unused")
            public Object getSelf() {
                throw new IllegalStateException("cannot serialize");
            }
        };

        assertDoesNotThrow(() ->
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