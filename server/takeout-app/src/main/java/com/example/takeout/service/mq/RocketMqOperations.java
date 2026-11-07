package com.example.takeout.service.mq;

import com.example.takeout.config.RocketMqConfiguration;
import com.example.takeout.dao.DomainEventInbox;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.annotation.PreDestroy;
import org.apache.rocketmq.client.consumer.DefaultMQPullConsumer;
import org.apache.rocketmq.client.consumer.PullStatus;
import org.apache.rocketmq.client.exception.MQClientException;
import org.apache.rocketmq.client.producer.DefaultMQProducer;
import org.apache.rocketmq.client.producer.SendStatus;
import org.apache.rocketmq.common.message.Message;
import org.apache.rocketmq.common.message.MessageQueue;
import org.apache.rocketmq.remoting.protocol.ResponseCode;
import org.apache.rocketmq.remoting.protocol.admin.OffsetWrapper;
import org.apache.rocketmq.remoting.protocol.admin.TopicOffset;
import org.apache.rocketmq.tools.admin.DefaultMQAdminExt;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.Comparator;
import java.util.HashMap;
import java.util.Map;

/** Broker reads happen on refresh, never on Prometheus scrapes. Replay owns a durable broker cursor. */
@Service
@ConditionalOnProperty(name = "takeout.mq.enabled", havingValue = "true", matchIfMissing = true)
public class RocketMqOperations {
    private static final Logger log = LoggerFactory.getLogger(RocketMqOperations.class);
    private final RocketMqConfiguration configuration;
    private final DefaultMQProducer producer;
    private final ObjectMapper mapper;
    private final DomainEventInbox inbox;
    private DefaultMQAdminExt admin;
    private DefaultMQPullConsumer replay;
    private boolean closed;
    private volatile Snapshot snapshot = new Snapshot(Double.NaN, Double.NaN, Double.NaN, Double.NaN, 0);
    public record Snapshot(double pending, double deadLetters, double failed, double oldestFailureSeconds, double available) { }

    public RocketMqOperations(RocketMqConfiguration configuration, DefaultMQProducer producer,
                              ObjectMapper mapper, MeterRegistry registry, DomainEventInbox inbox) {
        this.configuration = configuration;
        this.producer = producer;
        this.mapper = mapper;
        this.inbox = inbox;
        Gauge.builder("takeout.mq.consumer.pending", this, value -> value.snapshot.pending())
                .tag("group", configuration.consumerGroup()).register(registry);
        Gauge.builder("takeout.mq.dead.letters", this, value -> value.snapshot.deadLetters())
                .tag("group", configuration.consumerGroup()).register(registry);
        Gauge.builder("takeout.mq.collector.available", this, value -> value.snapshot.available())
                .tag("group", configuration.consumerGroup()).register(registry);
        Gauge.builder("takeout.mq.consumer.failed", this, value -> value.snapshot.failed())
                .tag("group", configuration.consumerGroup()).register(registry);
        Gauge.builder("takeout.mq.consumer.oldest.failure.seconds", this, value -> value.snapshot.oldestFailureSeconds())
                .tag("group", configuration.consumerGroup()).register(registry);
    }

    private void startClients() throws Exception {
        if (closed) throw new IllegalStateException("RocketMQ operations are closed");
        if (admin != null) return;
        var nextAdmin = configuration.newAdmin();
        var nextReplay = configuration.newReplayConsumer();
        try {
            nextAdmin.start();
            nextReplay.start();
            admin = nextAdmin;
            replay = nextReplay;
        } catch (Exception e) {
            nextReplay.shutdown();
            nextAdmin.shutdown();
            throw e;
        }
    }

    @Scheduled(fixedDelayString = "${takeout.mq.metrics-refresh-ms:30000}", initialDelay = 15000)
    public synchronized void refresh() {
        try {
            startClients();
            long pending = pending(configuration.topic()) + pending("%RETRY%" + configuration.consumerGroup());
            var deadLetters = topicOffsets(deadLetterTopic());
            long dead = 0;
            if (!deadLetters.isEmpty()) {
                replay.fetchSubscribeMessageQueues(deadLetterTopic());
                for (var entry : deadLetters.entrySet()) {
                    dead += Math.max(0, entry.getValue().getMaxOffset() - replayOffset(entry.getKey(), entry.getValue()));
                }
            }
            var failures = inbox.failures(configuration.consumerGroup());
            snapshot = new Snapshot(pending, dead, failures.count(), failures.oldestSeconds(), 1);
        } catch (Exception e) {
            snapshot = new Snapshot(Double.NaN, Double.NaN, Double.NaN, Double.NaN, 0);
            log.warn("[MQ指标] 采集失败，消费积压未知", e);
        }
    }

    private long pending(String topic) throws Exception {
        var queues = topicOffsets(topic);
        if (queues.isEmpty()) return 0;
        Map<MessageQueue, OffsetWrapper> consumed = new HashMap<>();
        for (var broker : admin.examineTopicRouteInfo(topic).getBrokerDatas()) {
            consumed.putAll(admin.examineConsumeStats(broker.selectBrokerAddr(),
                    configuration.consumerGroup(), topic, 3000).getOffsetTable());
        }
        long total = 0;
        for (var entry : queues.entrySet()) {
            var offset = consumed.get(entry.getKey());
            long committed = offset == null ? entry.getValue().getMinOffset() : offset.getConsumerOffset();
            total += Math.max(0, entry.getValue().getMaxOffset() - Math.max(committed, entry.getValue().getMinOffset()));
        }
        return total;
    }

    private Map<MessageQueue, TopicOffset> topicOffsets(String topic) throws Exception {
        try { return admin.examineTopicStats(topic).getOffsetTable(); }
        catch (MQClientException e) {
            // Retry/DLQ topics do not exist before the first failure. The primary topic must exist.
            if (e.getResponseCode() == ResponseCode.TOPIC_NOT_EXIST && !topic.equals(configuration.topic())) return Map.of();
            throw e;
        }
    }

    private long replayOffset(MessageQueue queue, TopicOffset bounds) throws Exception {
        var stats = admin.examineConsumeStats(brokerAddress(queue), configuration.replayGroup(), queue.getTopic(), 3000);
        var committed = stats.getOffsetTable().get(queue);
        return Math.max(bounds.getMinOffset(), committed == null ? bounds.getMinOffset() : committed.getConsumerOffset());
    }

    private String brokerAddress(MessageQueue queue) throws Exception {
        return admin.examineTopicRouteInfo(queue.getTopic()).getBrokerDatas().stream()
                .filter(value -> value.getBrokerName().equals(queue.getBrokerName()))
                .findFirst().orElseThrow().selectBrokerAddr();
    }

    /** Bounded at ten messages per request. Publication must be confirmed before advancing the cursor. */
    public synchronized int replayDeadLetters(int limit) throws Exception {
        if (limit < 1 || limit > 10) throw new IllegalArgumentException("Replay limit must be between 1 and 10");
        startClients();
        return inbox.serializeReplay(configuration.consumerGroup(), () -> replayBatch(limit));
    }

    private int replayBatch(int limit) throws Exception {
        var queues = topicOffsets(deadLetterTopic());
        if (queues.isEmpty()) return 0;
        replay.fetchSubscribeMessageQueues(deadLetterTopic());
        int sent = 0;
        var ordered = queues.keySet().stream().sorted(Comparator.comparing(MessageQueue::getBrokerName)
                .thenComparingInt(MessageQueue::getQueueId)).toList();
        for (var queue : ordered) {
            if (sent == limit) break;
            long offset = replayOffset(queue, queues.get(queue));
            var result = replay.pull(queue, "*", offset, limit - sent);
            if (result.getPullStatus() == PullStatus.NO_NEW_MSG) continue;
            if (result.getPullStatus() != PullStatus.FOUND) throw new IllegalStateException("Dead-letter offset is unavailable");
            for (var original : result.getMsgFoundList()) {
                DomainEvent event = mapper.readValue(original.getBody(), DomainEvent.class);
                if (event.eventId() <= 0 || event.orderId() <= 0 || event.eventType() == null || event.eventType().isBlank()) {
                    throw new IllegalArgumentException("Invalid dead-letter envelope; preserved for investigation");
                }
                var message = new Message(configuration.topic(), event.eventType(), "takeout-event-" + event.eventId(), original.getBody());
                var confirmation = producer.send(message);
                if (confirmation == null || confirmation.getSendStatus() != SendStatus.SEND_OK) {
                    throw new IllegalStateException("RocketMQ did not confirm replay; cursor retained");
                }
                long next = original.getQueueOffset() + 1;
                // Do not cache offsets in the pull client: another app's periodic flush could rewind this cursor.
                admin.updateConsumeOffset(brokerAddress(queue), configuration.replayGroup(), queue, next);
                sent++;
            }
        }
        refresh();
        return sent;
    }

    public Snapshot snapshot() { return snapshot; }
    private String deadLetterTopic() { return "%DLQ%" + configuration.consumerGroup(); }

    @PreDestroy public synchronized void shutdown() {
        closed = true;
        if (replay != null) replay.shutdown();
        if (admin != null) admin.shutdown();
    }
}
