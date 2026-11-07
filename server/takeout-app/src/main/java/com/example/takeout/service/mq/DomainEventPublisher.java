package com.example.takeout.service.mq;

import com.example.takeout.dao.OutboxEventDao;
import com.example.takeout.common.TraceContext;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.apache.rocketmq.client.producer.DefaultMQProducer;
import org.apache.rocketmq.client.producer.SendStatus;
import org.apache.rocketmq.common.message.Message;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/**
 * Events commit in the same MySQL transaction as the business data.
 * The durable Outbox retries delivery to RocketMQ; financial writes remain synchronous.
 * A broker outage delays downstream work without losing the committed event.
 */
@Service
public class DomainEventPublisher {

    private static final Logger log = LoggerFactory.getLogger(DomainEventPublisher.class);

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /** 事件类型常量。 */
    public static final String ORDER_CREATED = "ORDER_CREATED";
    public static final String ORDER_PAID = "ORDER_PAID";
    public static final String ORDER_CANCELLED = "ORDER_CANCELLED";
    public static final String ORDER_REFUNDED = "ORDER_REFUNDED";
    public static final String ORDER_SETTLED = "ORDER_SETTLED";

    private final OutboxEventDao outboxDao;
    private final ObjectProvider<DefaultMQProducer> producerProvider;
    private final ObjectMapper objectMapper;

    @Value("${takeout.mq.enabled:true}")
    private boolean enabled = true;

    @Value("${takeout.mq.topic:takeout-domain-events}")
    private String topic = "takeout-domain-events";

    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private com.example.takeout.service.ErpEventDelivery erpDelivery;

    public DomainEventPublisher(OutboxEventDao outboxDao, ObjectProvider<DefaultMQProducer> producerProvider,
                                ObjectMapper objectMapper) {
        this.outboxDao = outboxDao;
        this.producerProvider = producerProvider;
        this.objectMapper = objectMapper;
    }

    /**
     * 记录一个领域事件。
     *
     * <p>若当前处于事务中，事件会随事务一起提交（Outbox 语义）；
     * 若不在事务中，则立即落库并由后续中继投递。</p>
     */
    public void publish(String eventType, long orderId, Map<String, Object> payload) {
        if (!enabled) {
            return;
        }
        String json;
        try {
            Map<String,Object> fields = new java.util.LinkedHashMap<>(payload == null ? Map.of() : payload);
            // Persist correlation with the event; retries never depend on the originating HTTP thread.
            if (!TraceContext.current().isBlank()) fields.put("_traceId", TraceContext.current());
            json = objectMapper.writeValueAsString(fields);
        } catch (Exception e) {
            throw new IllegalStateException("Outbox event serialization failed", e);
        }
        try {
            outboxDao.insert(eventType, orderId, json, LocalDateTime.now().format(FMT));
        } catch (org.springframework.dao.DataAccessException e) {
            // MySQL 死锁可能已回滚整个事务，不能吞异常后继续返回业务成功。
            throw e;
        } catch (Exception e) {
            throw new IllegalStateException("Outbox event persistence failed", e);
        }
    }

    /**
     * 同步投递单条事件到 RocketMQ，仅 SEND_OK 才确认 Outbox（供中继任务调用）。
     *
     * @return true 表示投递成功
     */
    public boolean deliver(long eventId, String eventType, long orderId, String payloadJson) {
        DefaultMQProducer producer = producerProvider.getIfAvailable();
        if (producer == null) {
            return false;
        }
        String previous = TraceContext.current();
        String trace = null;
        try {
            var payload = objectMapper.readTree(payloadJson == null ? "{}" : payloadJson);
            if (payload != null) trace = TraceContext.normalize(payload.path("_traceId").asText(null));
        } catch (Exception ignored) {
            // Legacy events without valid metadata remain deliverable.
        }
        TraceContext.bind(trace == null ? "event-" + eventId : trace);
        try {
            if (erpDelivery != null && !erpDelivery.deliver(eventId,eventType,orderId,payloadJson)) return false;
            var envelope = new DomainEvent(eventId, eventType, orderId,
                    payloadJson == null ? "{}" : payloadJson, TraceContext.current());
            var message = new Message(topic, eventType, "takeout-event-" + eventId,
                    objectMapper.writeValueAsBytes(envelope));
            var result = producer.send(message);
            if (result == null || result.getSendStatus() != SendStatus.SEND_OK) {
                log.warn("[事件] RocketMQ 未确认持久化 eventId={} result={}（保留 Outbox 重试）", eventId, result);
                return false;
            }
            log.info("[事件] 投递完成 eventId={} type={}", eventId, eventType);
            return true;
        } catch (Exception e) {
            log.warn("[事件] ERP/RocketMQ 下游投递失败 eventId={} type={}（等待 Outbox 退避重试）", eventId, eventType, e);
            return false;
        } finally {
            TraceContext.clear();
            TraceContext.bind(previous);
        }
    }

    /** 供诊断使用：当前是否启用事件机制。 */
    public boolean isEnabled() {
        return enabled;
    }

    /**
     * 事务提交后再执行的动作（用于把「通知」等副作用推迟到提交之后）。
     * 事务提交后回调，回滚则不执行。
     */
    public static void afterCommit(Runnable action) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    action.run();
                }
            });
        } else {
            action.run();
        }
    }
}
