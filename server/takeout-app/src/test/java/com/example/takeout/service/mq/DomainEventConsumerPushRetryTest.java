package com.example.takeout.service.mq;

import com.example.takeout.common.TraceContext;
import com.example.takeout.config.RocketMqConfiguration;
import com.example.takeout.dao.DomainEventInbox;
import com.example.takeout.service.PushNotificationService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.rocketmq.client.consumer.DefaultMQPushConsumer;
import org.apache.rocketmq.client.consumer.listener.ConsumeConcurrentlyStatus;
import org.apache.rocketmq.common.message.MessageExt;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class DomainEventConsumerPushRetryTest {
    private final RocketMqConfiguration configuration = mock(RocketMqConfiguration.class);
    private final DomainEventInbox inbox = mock(DomainEventInbox.class);
    private final PushNotificationService notifications = mock(PushNotificationService.class);
    private DomainEventConsumer consumer;

    @BeforeEach @SuppressWarnings("unchecked")
    void setUp() {
        ObjectProvider<PushNotificationService> pushProvider = mock(ObjectProvider.class);
        when(pushProvider.getIfAvailable()).thenReturn(notifications);
        when(configuration.consumerGroup()).thenReturn("takeout-notifications");
        doAnswer(invocation -> { invocation.<Runnable>getArgument(2).run(); return null; })
                .when(inbox).runOnce(anyString(), anyLong(), any(Runnable.class));
        consumer = new DomainEventConsumer(configuration, inbox, new ObjectMapper(), pushProvider);
        consumer.applicationReady();
    }

    @AfterEach void close() { consumer.shutdown(); TraceContext.clear(); }

    @Test void failedPushIsRetriedBeforeAcknowledgement() throws Exception {
        doThrow(new IllegalStateException("injected offline push")).doNothing().when(notifications)
                .notifyOrderEvent(DomainEventPublisher.ORDER_PAID, 21);
        var messages = List.of(message(17, "ORDER_PAID"));
        assertEquals(ConsumeConcurrentlyStatus.RECONSUME_LATER, consumer.consumeMessage(messages, null));
        assertEquals(ConsumeConcurrentlyStatus.CONSUME_SUCCESS, consumer.consumeMessage(messages, null));
        verify(notifications, times(2)).notifyOrderEvent(DomainEventPublisher.ORDER_PAID, 21);
    }

    @Test void databaseFailureDoesNotAcknowledgeMessage() throws Exception {
        doThrow(new IllegalStateException("injected database failure")).when(inbox)
                .runOnce(anyString(), anyLong(), any(Runnable.class));
        assertEquals(ConsumeConcurrentlyStatus.RECONSUME_LATER,
                consumer.consumeMessage(List.of(message(17, "ORDER_PAID")), null));
        verifyNoInteractions(notifications);
    }

    @Test void failedPushRecordsTheOriginalEventAndSuccessClearsTheMessageFailure() throws Exception {
        var message = message(17, "ORDER_PAID");
        message.setMsgId("origin-id");
        doThrow(new IllegalStateException("push offline")).doNothing().when(notifications)
                .notifyOrderEvent("ORDER_PAID", 21);
        assertEquals(ConsumeConcurrentlyStatus.RECONSUME_LATER, consumer.consumeMessage(List.of(message), null));
        verify(inbox).recordFailure("takeout-notifications", "event-17", 17);
        assertEquals(ConsumeConcurrentlyStatus.CONSUME_SUCCESS, consumer.consumeMessage(List.of(message), null));
        verify(inbox).resolveFailure("takeout-notifications", DomainEventInbox.failureKey(0, "origin-id"));
    }

    @Test void malformedRetriesUseTheStableOriginalMessageIdentity() {
        for (String id : List.of("physical-1", "physical-2")) {
            var message = new MessageExt();
            message.setMsgId(id);
            org.apache.rocketmq.common.message.MessageAccessor.putProperty(message,
                    org.apache.rocketmq.common.message.MessageConst.PROPERTY_ORIGIN_MESSAGE_ID, "stable-origin");
            message.setBody("invalid JSON".getBytes(StandardCharsets.UTF_8));
            assertEquals(ConsumeConcurrentlyStatus.RECONSUME_LATER, consumer.consumeMessage(List.of(message), null));
        }
        verify(inbox, times(2)).recordFailure("takeout-notifications", DomainEventInbox.failureKey(0, "stable-origin"), 0);
    }

    @Test void uniqueClientIdentityWinsOverDifferentPhysicalOriginIds() {
        for (String origin : List.of("", "physical-offset-id")) {
            var message = new org.apache.rocketmq.common.message.MessageClientExt();
            message.setOffsetMsgId(origin.isBlank() ? "physical-offset-id" : "another-offset-id");
            org.apache.rocketmq.common.message.MessageAccessor.putProperty(message,
                    org.apache.rocketmq.common.message.MessageConst.PROPERTY_UNIQ_CLIENT_MESSAGE_ID_KEYIDX, "client-id");
            if (!origin.isBlank()) org.apache.rocketmq.common.message.MessageAccessor.putProperty(message,
                    org.apache.rocketmq.common.message.MessageConst.PROPERTY_ORIGIN_MESSAGE_ID, origin);
            message.setBody("invalid JSON".getBytes(StandardCharsets.UTF_8));
            assertEquals(ConsumeConcurrentlyStatus.RECONSUME_LATER, consumer.consumeMessage(List.of(message), null));
        }
        verify(inbox, times(2)).recordFailure("takeout-notifications", DomainEventInbox.failureKey(0, "client-id"), 0);
    }

    @Test void failureTrackingOutageUsesAShortBrokerRetryInsteadOfLongInvisibleBackoff() throws Exception {
        doThrow(new IllegalStateException("push offline")).when(notifications).notifyOrderEvent(anyString(), anyLong());
        doThrow(new org.springframework.dao.DataAccessResourceFailureException("tracking DB unavailable"))
                .when(inbox).recordFailure(anyString(), anyString(), anyLong());
        var context = new org.apache.rocketmq.client.consumer.listener.ConsumeConcurrentlyContext(
                new org.apache.rocketmq.common.message.MessageQueue("events", "broker", 0));
        assertEquals(ConsumeConcurrentlyStatus.RECONSUME_LATER,
                consumer.consumeMessage(List.of(message(17, "ORDER_PAID")), context));
        assertEquals(1, context.getDelayLevelWhenNextConsume());
    }

    @Test void consumerDoesNotStartBeforeSchemaMigrationAndApplicationReady() throws Exception {
        ReflectionTestUtils.setField(consumer, "ready", false);
        consumer.startConsumer();
        verify(configuration, never()).newConsumer();
        when(configuration.newConsumer()).thenReturn(mock(DefaultMQPushConsumer.class));
        consumer.applicationReady();
        consumer.startConsumer();
        verify(configuration).newConsumer();
    }

    @Test void invalidMessagesAreRetriedForDeadLetterHandling() throws Exception {
        var malformed = new MessageExt();
        malformed.setBody("invalid JSON".getBytes(StandardCharsets.UTF_8));
        for (MessageExt message : List.of(malformed, message(0, "ORDER_PAID"), message(17, "UNKNOWN"))) {
            assertEquals(ConsumeConcurrentlyStatus.RECONSUME_LATER,
                    consumer.consumeMessage(List.of(message), null));
        }
        verify(inbox, times(3)).recordFailure(anyString(), anyString(), anyLong());
        verify(inbox, never()).runOnce(anyString(), anyLong(), any());
        verifyNoInteractions(notifications);
    }

    @Test void restoresTraceOnSuccessfulAndFailedConsumption() throws Exception {
        TraceContext.bind("caller");
        doAnswer(invocation -> { assertEquals("origin", TraceContext.current()); return null; })
                .doThrow(new IllegalStateException("injected push failure")).when(notifications)
                .notifyOrderEvent(anyString(), anyLong());
        assertEquals(ConsumeConcurrentlyStatus.CONSUME_SUCCESS,
                consumer.consumeMessage(List.of(message(17, "ORDER_PAID")), null));
        assertEquals("caller", TraceContext.current());
        assertEquals(ConsumeConcurrentlyStatus.RECONSUME_LATER,
                consumer.consumeMessage(List.of(message(18, "ORDER_PAID")), null));
        assertEquals("caller", TraceContext.current());
    }

    @Test void retriesFailedStartupWithFreshClientAndClosesItOnlyOnce() throws Exception {
        var failed = mock(DefaultMQPushConsumer.class);
        var healthy = mock(DefaultMQPushConsumer.class);
        when(configuration.newConsumer()).thenReturn(failed, healthy);
        doThrow(new IllegalStateException("broker unavailable")).when(failed).start();
        consumer.startConsumer();
        consumer.startConsumer();
        consumer.startConsumer();
        verify(configuration, times(2)).newConsumer();
        verify(failed).shutdown();
        verify(healthy).start();
        consumer.shutdown();
        consumer.startConsumer();
        verify(configuration, times(2)).newConsumer();
    }

    @Test void disabledConsumerDoesNotStart() throws Exception {
        ReflectionTestUtils.setField(consumer, "enabled", false);
        consumer.startConsumer();
        verify(configuration, never()).newConsumer();
    }

    private MessageExt message(long id, String type) throws Exception {
        var message = new MessageExt();
        message.setBody(new ObjectMapper().writeValueAsBytes(new DomainEvent(id, type, 21, "{}", "origin")));
        return message;
    }
}
