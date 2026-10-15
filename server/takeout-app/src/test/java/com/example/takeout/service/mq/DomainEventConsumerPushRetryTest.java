package com.example.takeout.service.mq;

import com.example.takeout.service.PushNotificationService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.connection.stream.*;
import org.springframework.data.redis.core.StreamOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class DomainEventConsumerPushRetryTest {
    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void failedPushIsRetriedFromPendingBeforeAcknowledgement() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        StreamOperations<String, Object, Object> stream = mock(StreamOperations.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        when(redis.opsForStream()).thenReturn(stream);
        when(redis.opsForValue()).thenReturn(values);
        when(redis.hasKey(DomainEventPublisher.STREAM_KEY)).thenReturn(true);
        when(values.setIfAbsent(anyString(), eq("processing"), any(Duration.class))).thenReturn(true);
        MapRecord<String, Object, Object> record = StreamRecords.mapBacked(Map.<Object, Object>of(
                        "eventId", "17", "eventType", DomainEventPublisher.ORDER_PAID, "orderId", "21"))
                .withStreamKey(DomainEventPublisher.STREAM_KEY).withId(RecordId.of("1-0"));
        when(stream.read(any(Consumer.class), any(StreamReadOptions.class), any(StreamOffset.class)))
                .thenReturn(List.of(), List.of(record), List.of(record), List.of());
        PushNotificationService notifications = mock(PushNotificationService.class);
        doThrow(new IllegalStateException("offline")).doNothing().when(notifications)
                .notifyOrderEvent(DomainEventPublisher.ORDER_PAID, 21);
        ObjectProvider<StringRedisTemplate> redisProvider = mock(ObjectProvider.class);
        when(redisProvider.getIfAvailable()).thenReturn(redis);
        ObjectProvider<PushNotificationService> pushProvider = mock(ObjectProvider.class);
        when(pushProvider.getIfAvailable()).thenReturn(notifications);
        DomainEventConsumer consumer = new DomainEventConsumer(redisProvider, pushProvider);

        consumer.consume();
        verify(stream, never()).acknowledge(anyString(), anyString(), any(RecordId.class));
        verify(redis).delete("takeout:event:consumed:17");
        consumer.consume();
        verify(notifications, times(2)).notifyOrderEvent(DomainEventPublisher.ORDER_PAID, 21);
        verify(stream).acknowledge(DomainEventPublisher.STREAM_KEY, "takeout-consumers", RecordId.of("1-0"));
        verify(values).set("takeout:event:consumed:17", "done", Duration.ofHours(24));
    }
}
