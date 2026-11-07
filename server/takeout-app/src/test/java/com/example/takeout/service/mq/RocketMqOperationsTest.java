package com.example.takeout.service.mq;

import com.example.takeout.config.RocketMqConfiguration;
import com.example.takeout.dao.DomainEventInbox;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.apache.rocketmq.client.consumer.DefaultMQPullConsumer;
import org.apache.rocketmq.client.consumer.PullResult;
import org.apache.rocketmq.client.consumer.PullStatus;
import org.apache.rocketmq.client.exception.MQClientException;
import org.apache.rocketmq.client.producer.DefaultMQProducer;
import org.apache.rocketmq.client.producer.SendResult;
import org.apache.rocketmq.client.producer.SendStatus;
import org.apache.rocketmq.common.message.Message;
import org.apache.rocketmq.common.message.MessageExt;
import org.apache.rocketmq.common.message.MessageQueue;
import org.apache.rocketmq.remoting.protocol.ResponseCode;
import org.apache.rocketmq.remoting.protocol.admin.ConsumeStats;
import org.apache.rocketmq.remoting.protocol.admin.TopicOffset;
import org.apache.rocketmq.remoting.protocol.admin.TopicStatsTable;
import org.apache.rocketmq.remoting.protocol.route.BrokerData;
import org.apache.rocketmq.remoting.protocol.route.TopicRouteData;
import org.apache.rocketmq.tools.admin.DefaultMQAdminExt;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.HashMap;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class RocketMqOperationsTest {
    private final DefaultMQAdminExt admin = mock(DefaultMQAdminExt.class);
    private final DefaultMQPullConsumer replay = mock(DefaultMQPullConsumer.class);
    private final DefaultMQProducer producer = mock(DefaultMQProducer.class);
    private final SimpleMeterRegistry registry = new SimpleMeterRegistry();
    private final MessageQueue normal = new MessageQueue("events", "broker", 0);
    private final MessageQueue dead = new MessageQueue("%DLQ%notifications", "broker", 0);
    private final DomainEventInbox inbox = mock(DomainEventInbox.class);
    private RocketMqOperations operations;

    @BeforeEach void open() throws Exception {
        var configuration = mock(RocketMqConfiguration.class);
        when(configuration.topic()).thenReturn("events");
        when(configuration.consumerGroup()).thenReturn("notifications");
        when(configuration.replayGroup()).thenReturn("notifications-replay");
        when(configuration.newAdmin()).thenReturn(admin);
        when(configuration.newReplayConsumer()).thenReturn(replay);
        var route = new TopicRouteData();
        var addresses = new HashMap<Long, String>();
        addresses.put(0L, "broker:10911");
        route.setBrokerDatas(List.of(new BrokerData("cluster", "broker", addresses)));
        when(admin.examineTopicRouteInfo(anyString())).thenReturn(route);
        when(admin.examineTopicStats("events")).thenReturn(bounds(normal, 4));
        when(admin.examineTopicStats("%RETRY%notifications"))
                .thenThrow(new MQClientException(ResponseCode.TOPIC_NOT_EXIST, "not created"));
        when(admin.examineTopicStats("%DLQ%notifications")).thenReturn(bounds(dead, 1));
        when(admin.examineConsumeStats(anyString(), anyString(), anyString(), anyLong())).thenReturn(new ConsumeStats());
        var message = new MessageExt();
        message.setQueueOffset(0);
        message.setBody(new ObjectMapper().writeValueAsBytes(new DomainEvent(17, "ORDER_PAID", 21, "{}", "trace")));
        when(replay.pull(dead, "*", 0L, 10)).thenReturn(new PullResult(PullStatus.FOUND, 1, 0, 1, List.of(message)));
        var confirmation = new SendResult();
        confirmation.setSendStatus(SendStatus.SEND_OK);
        when(producer.send(any(Message.class))).thenReturn(confirmation);
        when(inbox.failures(anyString())).thenReturn(new DomainEventInbox.FailureStats(0, 0));
        doAnswer(call -> call.<java.util.concurrent.Callable<Integer>>getArgument(1).call())
                .when(inbox).serializeReplay(anyString(), any());
        operations = new RocketMqOperations(configuration, producer, new ObjectMapper(), registry, inbox);
    }

    @AfterEach void close() { operations.shutdown(); registry.close(); }

    @Test void metricsIncludeUnconsumedBrokerMessagesAndUnreplayedDeadLetters() {
        operations.refresh();
        assertEquals(4, registry.get("takeout.mq.consumer.pending").gauge().value());
        assertEquals(1, registry.get("takeout.mq.dead.letters").gauge().value());
        assertEquals(1, registry.get("takeout.mq.collector.available").gauge().value());
    }

    @Test void failedCollectionDoesNotReportAHealthyZeroBacklog() throws Exception {
        when(admin.examineTopicStats("events")).thenThrow(new IllegalStateException("injected unreachable broker"));
        operations.refresh();
        assertTrue(Double.isNaN(registry.get("takeout.mq.consumer.pending").gauge().value()));
        assertTrue(Double.isNaN(registry.get("takeout.mq.dead.letters").gauge().value()));
        assertEquals(0, registry.get("takeout.mq.collector.available").gauge().value());
    }

    @Test void delayedRetriesRemainVisibleThroughDurableFailuresEvenWithEmptyBrokerQueues() throws Exception {
        when(admin.examineTopicStats("events")).thenReturn(bounds(normal, 0));
        when(admin.examineTopicStats("%DLQ%notifications")).thenReturn(new TopicStatsTable());
        when(inbox.failures("notifications")).thenReturn(new DomainEventInbox.FailureStats(1, 1200));
        operations.refresh();
        assertEquals(0, operations.snapshot().pending());
        assertEquals(0, operations.snapshot().deadLetters());
        assertEquals(1, operations.snapshot().failed());
        assertEquals(1200, registry.get("takeout.mq.consumer.oldest.failure.seconds").gauge().value());
        assertEquals(1, registry.get("takeout.mq.consumer.failed").gauge().value());
        assertEquals(1, operations.snapshot().available());
    }

    @Test void unavailableReplayLockRejectsBeforeReadingOrPublishingAnyDeadLetter() throws Exception {
        doThrow(new org.springframework.dao.CannotAcquireLockException("injected lock unavailable"))
                .when(inbox).serializeReplay(anyString(), any());
        assertThrows(org.springframework.dao.CannotAcquireLockException.class, () -> operations.replayDeadLetters(10));
        verify(admin, never()).examineTopicStats(anyString());
        verifyNoInteractions(producer);
    }

    @Test void replayPreservesEnvelopeAndCommitsOnlyAfterBrokerConfirmation() throws Exception {
        assertEquals(1, operations.replayDeadLetters(10));
        var message = ArgumentCaptor.forClass(Message.class);
        verify(producer).send(message.capture());
        var event = new ObjectMapper().readValue(message.getValue().getBody(), DomainEvent.class);
        assertEquals(new DomainEvent(17, "ORDER_PAID", 21, "{}", "trace"), event);
        assertEquals("takeout-event-17", message.getValue().getKeys());
        var ordered = inOrder(producer, admin);
        ordered.verify(producer).send(any(Message.class));
        ordered.verify(admin).updateConsumeOffset("broker:10911", "notifications-replay", dead, 1L);
    }

    @Test void failedPublicationRetainsCursorAndCanBeRetried() throws Exception {
        var failed = new SendResult();
        failed.setSendStatus(SendStatus.FLUSH_DISK_TIMEOUT);
        when(producer.send(any(Message.class))).thenReturn(failed);
        assertThrows(IllegalStateException.class, () -> operations.replayDeadLetters(10));
        verify(replay, never()).updateConsumeOffset(any(), anyLong());
        verify(admin, never()).updateConsumeOffset(anyString(), anyString(), any(), anyLong());
        var confirmed = new SendResult();
        confirmed.setSendStatus(SendStatus.SEND_OK);
        when(producer.send(any(Message.class))).thenReturn(confirmed);
        assertEquals(1, operations.replayDeadLetters(10));
        verify(admin).updateConsumeOffset("broker:10911", "notifications-replay", dead, 1L);
    }

    @Test void invalidEnvelopeIsPreservedForInvestigation() throws Exception {
        var malformed = new MessageExt();
        malformed.setBody("{}".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        when(replay.pull(dead, "*", 0L, 10)).thenReturn(new PullResult(PullStatus.FOUND, 1, 0, 1, List.of(malformed)));
        assertThrows(IllegalArgumentException.class, () -> operations.replayDeadLetters(10));
        verifyNoInteractions(producer);
        verify(admin, never()).updateConsumeOffset(anyString(), anyString(), any(), anyLong());
    }

    @Test void cursorCommitFailureAllowsSafeReplayOfTheSameOriginalEvent() throws Exception {
        doThrow(new IllegalStateException("injected cursor commit failure")).doNothing().when(admin)
                .updateConsumeOffset(anyString(), anyString(), any(), anyLong());
        assertThrows(IllegalStateException.class, () -> operations.replayDeadLetters(10));
        assertEquals(1, operations.replayDeadLetters(10));
        var messages = ArgumentCaptor.forClass(Message.class);
        verify(producer, times(2)).send(messages.capture());
        assertArrayEquals(messages.getAllValues().get(0).getBody(), messages.getAllValues().get(1).getBody());
        verify(replay, never()).updateConsumeOffset(any(), anyLong());
    }

    @Test void replayLimitsAreValidatedBeforeAnyRemoteWork() {
        for (int limit : List.of(0, 11)) assertThrows(IllegalArgumentException.class, () -> operations.replayDeadLetters(limit));
        verifyNoInteractions(admin, replay, producer);
    }

    private TopicStatsTable bounds(MessageQueue queue, long max) {
        var table = new TopicStatsTable();
        var offset = new TopicOffset();
        offset.setMinOffset(0);
        offset.setMaxOffset(max);
        table.getOffsetTable().put(queue, offset);
        return table;
    }
}
