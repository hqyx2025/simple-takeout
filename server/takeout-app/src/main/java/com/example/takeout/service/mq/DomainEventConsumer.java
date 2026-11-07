package com.example.takeout.service.mq;

import com.example.takeout.common.TraceContext;
import com.example.takeout.config.RocketMqConfiguration;
import com.example.takeout.dao.DomainEventInbox;
import com.example.takeout.service.PushNotificationService;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PreDestroy;
import org.apache.rocketmq.client.consumer.DefaultMQPushConsumer;
import org.apache.rocketmq.client.consumer.listener.ConsumeConcurrentlyContext;
import org.apache.rocketmq.client.consumer.listener.ConsumeConcurrentlyStatus;
import org.apache.rocketmq.client.consumer.listener.MessageListenerConcurrently;
import org.apache.rocketmq.common.message.MessageExt;
import org.apache.rocketmq.common.message.MessageConst;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;

import java.util.List;
import java.util.Set;

/** Notifications only. RocketMQ owns retries and DLQ; MySQL owns durable consumption receipts. */
@Component
public class DomainEventConsumer implements MessageListenerConcurrently {
    private static final Logger log = LoggerFactory.getLogger(DomainEventConsumer.class);
    private static final Set<String> TYPES = Set.of(DomainEventPublisher.ORDER_CREATED,
            DomainEventPublisher.ORDER_PAID, DomainEventPublisher.ORDER_CANCELLED,
            DomainEventPublisher.ORDER_REFUNDED, DomainEventPublisher.ORDER_SETTLED);

    private final RocketMqConfiguration configuration;
    private final DomainEventInbox inbox;
    private final ObjectMapper objectMapper;
    private final ObjectProvider<PushNotificationService> pushNotifications;
    private DefaultMQPushConsumer consumer;
    private boolean closed;
    private volatile boolean ready;

    @Value("${takeout.mq.enabled:true}")
    private boolean enabled = true;

    public DomainEventConsumer(RocketMqConfiguration configuration, DomainEventInbox inbox,
                               ObjectMapper objectMapper, ObjectProvider<PushNotificationService> pushNotifications) {
        this.configuration = configuration;
        this.inbox = inbox;
        this.objectMapper = objectMapper;
        this.pushNotifications = pushNotifications;
    }

    // Broker downtime must not prevent the application from accepting local business transactions.
    @EventListener(ApplicationReadyEvent.class)
    public void applicationReady() { ready = true; }

    @Scheduled(fixedDelayString = "${takeout.mq.consumer-start-retry-ms:30000}",
            initialDelayString = "${takeout.mq.consumer-initial-ms:15000}")
    public synchronized void startConsumer() {
        if (!ready || !enabled || closed || consumer != null) return;
        DefaultMQPushConsumer candidate = null;
        try {
            candidate = configuration.newConsumer();
            candidate.registerMessageListener(this);
            candidate.start();
            consumer = candidate;
            log.info("[事件消费] RocketMQ 已启动 group={} topic={}", configuration.consumerGroup(), configuration.topic());
        } catch (Exception e) {
            if (candidate != null) candidate.shutdown();
            log.warn("[事件消费] RocketMQ 启动失败，将重试", e);
        }
    }

    @Override
    public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> messages, ConsumeConcurrentlyContext context) {
        for (MessageExt message : messages) {
            String previous = TraceContext.current();
            DomainEvent event = null;
            // UNIQ_KEY survives retries; ORIGIN_MESSAGE_ID may instead contain the original physical offset ID.
            String identity = message.getProperty(MessageConst.PROPERTY_UNIQ_CLIENT_MESSAGE_ID_KEYIDX);
            if (identity == null || identity.isBlank()) identity = message.getProperty(MessageConst.PROPERTY_ORIGIN_MESSAGE_ID);
            if (identity == null || identity.isBlank()) identity = message.getMsgId();
            String messageKey = DomainEventInbox.failureKey(0, String.valueOf(identity));
            try {
                event = objectMapper.readValue(message.getBody(), DomainEvent.class);
                if (event.eventId() <= 0 || event.orderId() <= 0 || event.eventType() == null
                        || !TYPES.contains(event.eventType())) {
                    throw new IllegalArgumentException("Invalid domain event: " + message.getMsgId());
                }
                String trace = TraceContext.normalize(event.traceId());
                TraceContext.bind(trace == null ? "event-" + event.eventId() : trace);
                DomainEvent current = event;
                inbox.runOnce(configuration.consumerGroup(), current.eventId(), () -> {
                    PushNotificationService notifications = pushNotifications.getIfAvailable();
                    if (notifications != null) notifications.notifyOrderEvent(current.eventType(), current.orderId());
                });
                inbox.resolveFailure(configuration.consumerGroup(), messageKey);
            } catch (Exception e) {
                try {
                    long eventId = event == null ? 0 : event.eventId();
                    inbox.recordFailure(configuration.consumerGroup(), eventId > 0
                            ? DomainEventInbox.failureKey(eventId, "") : messageKey, eventId);
                } catch (Exception recordingFailure) {
                    // Do not hide an unrecorded failure in a 20-minute backoff. The retry budget/DLQ still applies.
                    if (context != null) context.setDelayLevelWhenNextConsume(1);
                    log.warn("[事件消费] 失败状态写入未完成，消息仍交由 Broker 重试", recordingFailure);
                }
                log.warn("[事件消费] 处理失败，将由 RocketMQ 重投 msgId={} attempts={}",
                        message.getMsgId(), message.getReconsumeTimes(), e);
                return ConsumeConcurrentlyStatus.RECONSUME_LATER;
            } finally {
                TraceContext.clear();
                TraceContext.bind(previous);
            }
        }
        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
    }

    @PreDestroy
    public synchronized void shutdown() {
        closed = true;
        if (consumer != null) consumer.shutdown();
    }
}
