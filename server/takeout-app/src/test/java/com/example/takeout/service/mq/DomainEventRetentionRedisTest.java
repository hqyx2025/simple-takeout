package com.example.takeout.service.mq;

import com.example.takeout.dao.OutboxEventDao;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.domain.Range;
import org.springframework.data.redis.connection.RedisStandaloneConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.connection.stream.*;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named="TAKEOUT_TEST_REDIS_PORT",matches="\\d+")
class DomainEventRetentionRedisTest {
    @Test void neverTrimsUnclaimedOrPendingEventsAndReclaimsAcknowledgedHistoryInBoundedBatches() {
        var configuration=new RedisStandaloneConfiguration("127.0.0.1",Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        configuration.setDatabase(14);
        var connection=new LettuceConnectionFactory(configuration);connection.afterPropertiesSet();connection.start();
        var redis=new StringRedisTemplate(connection); String key=DomainEventPublisher.STREAM_KEY;
        try {
            redis.delete(key);
            @SuppressWarnings("unchecked") ObjectProvider<StringRedisTemplate> provider=mock(ObjectProvider.class);
            when(provider.getIfAvailable()).thenReturn(redis);
            var publisher=new DomainEventPublisher(mock(OutboxEventDao.class),provider,new ObjectMapper());
            ReflectionTestUtils.setField(publisher,"streamMaxLen",2L);
            for(int id=1;id<=240;id++)assertTrue(publisher.deliver(id,DomainEventPublisher.ORDER_CREATED,id,"{}"));
            assertEquals(240,redis.opsForStream().size(key),"a late consumer must still receive the full durable backlog");
            String group="retention-test";
            redis.opsForStream().createGroup(key,ReadOffset.from("0"),group);
            var first=redis.opsForStream().read(Consumer.from(group,"worker"),StreamReadOptions.empty().count(2),StreamOffset.create(key,ReadOffset.lastConsumed()));
            assertNotNull(first); assertEquals(2,first.size());
            redis.opsForStream().acknowledge(key,group,first.get(1).getId());
            assertTrue(publisher.deliver(241,DomainEventPublisher.ORDER_CREATED,241,"{}"));
            assertFalse(redis.opsForStream().range(key,Range.closed(first.getFirst().getId().getValue(),first.getFirst().getId().getValue())).isEmpty(),"pending record must remain recoverable");
            redis.opsForStream().acknowledge(key,group,first.getFirst().getId());
            assertTrue(publisher.deliver(242,DomainEventPublisher.ORDER_CREATED,242,"{}"));
            var unread=redis.opsForStream().read(Consumer.from(group,"worker"),StreamReadOptions.empty().count(300),StreamOffset.create(key,ReadOffset.lastConsumed()));
            assertNotNull(unread);assertEquals(240,unread.size(),"all unread records must survive retention");
            redis.opsForStream().acknowledge(key,group,unread.stream().map(MapRecord::getId).toArray(RecordId[]::new));
            for(int id=243;id<=248;id++) {
                assertTrue(publisher.deliver(id,DomainEventPublisher.ORDER_CREATED,id,"{}"));
                var next=redis.opsForStream().read(Consumer.from(group,"worker"),StreamReadOptions.empty().count(1),StreamOffset.create(key,ReadOffset.lastConsumed()));
                assertNotNull(next);assertEquals(1,next.size());
                redis.opsForStream().acknowledge(key,group,next.getFirst().getId());
            }
            assertTrue(redis.opsForStream().size(key)<=3,"acknowledged history must converge to the retention target plus its boundary record");
            assertEquals(0,redis.opsForStream().pending(key,group).getTotalPendingMessages());
        } finally {redis.delete(key);connection.destroy();}
    }
}
