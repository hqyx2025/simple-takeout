package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.common.SchedulerLock;
import com.example.takeout.dao.OutboxEventDao;
import com.example.takeout.job.OutboxRelayJob;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class BackgroundCapacityTest {
    @Test void warmPublicCatalogDoesNotWaitOrReloadWhileAnotherInstanceRebuilds() {
        var redis=mock(org.springframework.data.redis.core.StringRedisTemplate.class);
        var values=mock(org.springframework.data.redis.core.ValueOperations.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.setIfAbsent(anyString(),anyString(),any(java.time.Duration.class))).thenReturn(false);
        ObjectProvider<org.springframework.data.redis.core.StringRedisTemplate> provider=mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);
        var cache=new HotDataCacheService(provider,new ObjectMapper());
        var type=new TypeReference<List<String>>() {};
        assertEquals(List.of("previous"),cache.get("catalog",type,()->List.of("previous")));
        assertEquals(List.of("previous"),cache.get("catalog",type,()->{throw new AssertionError("competing rebuild must use bounded catalog snapshot");}));
        cache.evictAll();
        assertEquals(List.of("current"),cache.get("catalog",type,()->List.of("current")));
    }

    @Test void relayDrainsBeyondTenAndIsolatesFailedEventsWithBoundedParallelism() {
        var dao = mock(OutboxEventDao.class);
        var publisher = mock(DomainEventPublisher.class);
        when(publisher.isEnabled()).thenReturn(true);
        var queue = new ConcurrentLinkedQueue<OutboxEventDao.OutboxEvent>();
        for (int i=1;i<=60;i++) queue.add(new OutboxEventDao.OutboxEvent(i,"ORDER_CREATED",i,"{}",0,0,"now"));
        var owners = new ConcurrentHashMap<Long,String>();
        when(dao.claimPending(anyInt(),anyString(),anyLong(),anyLong())).thenAnswer(call -> {
            List<OutboxEventDao.OutboxEvent> batch = new ArrayList<>();
            for (int i=0;i<(int)call.getArgument(0);i++) {
                var event=queue.poll(); if (event==null) break;
                batch.add(event); owners.put(event.id(),call.getArgument(1));
            }
            return batch;
        });
        AtomicInteger active = new AtomicInteger(), maximum = new AtomicInteger();
        when(publisher.deliver(anyLong(),anyString(),anyLong(),anyString())).thenAnswer(call -> {
            maximum.accumulateAndGet(active.incrementAndGet(),Math::max);
            try { Thread.sleep(5); return (long)call.getArgument(0)!=3; }
            finally { active.decrementAndGet(); }
        });
        var relay=new OutboxRelayJob(dao,publisher,mock(SchedulerLock.class));
        try {
            ReflectionTestUtils.setField(relay,"batchSize",100);
            relay.relay();
            assertTrue(queue.isEmpty()); assertTrue(maximum.get()>1 && maximum.get()<=4);
            verify(dao,times(59)).markSent(anyLong(),anyString());
            verify(dao).markRetry(3,owners.get(3L),0);
            for (var owner:owners.values()) assertTrue(owner.length()<=64);
        } finally { relay.close(); }
    }

    @Test void cacheFailureCannotCreateAnUnboundedDatabaseFallback() throws Exception {
        var cache=new HotDataCacheService(mock(ObjectProvider.class),new ObjectMapper());
        var type=new TypeReference<List<String>>() {};
        assertEquals(List.of("previous"),cache.get("catalog",type,()->List.of("previous")));
        var started=new CountDownLatch(4); var release=new CountDownLatch(1);
        try (var pool=Executors.newFixedThreadPool(4)) {
            var calls=new ArrayList<Future<List<String>>>();
            for(int i=0;i<4;i++) {
                String key="slow-"+i;
                calls.add(pool.submit(()->cache.get(key,type,()->{
                    started.countDown();
                    try { if(!release.await(5,TimeUnit.SECONDS)) throw new AssertionError("test release timed out"); }
                    catch(InterruptedException e) { throw new RuntimeException(e); }
                    return List.of(key);
                })));
            }
            try {
                assertTrue(started.await(5,TimeUnit.SECONDS));
                assertEquals(List.of("previous"),cache.get("catalog",type,()->{throw new AssertionError("must not load");}));
                assertEquals(503,assertThrows(BizException.class,()->cache.get("missing",type,List::of)).getCode());
                cache.evictByPattern("goods:*");
                assertEquals(503,assertThrows(BizException.class,()->cache.get("catalog",type,List::of)).getCode());
            } finally { release.countDown(); }
            for(var call:calls) call.get(5,TimeUnit.SECONDS);
        }
        assertEquals(List.of("fresh"),cache.get("catalog",type,()->List.of("fresh")));
    }
}
