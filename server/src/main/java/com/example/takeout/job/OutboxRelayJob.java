package com.example.takeout.job;

import com.example.takeout.dao.OutboxEventDao;
import com.example.takeout.service.mq.DomainEventPublisher;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * Outbox 中继：把数据库里待投递的领域事件搬运到 Redis Stream。
 *
 * <p>投递采用「至少一次」语义：投递成功即置 status=1。
 * 若在投递成功后、置位前崩溃，事件会被重复投递，因此
 * 消费端必须按 eventId 做幂等（见 {@link com.example.takeout.service.mq.DomainEventConsumer}）。</p>
 *
 * <p>Redis 不可用时事件保留在表中等待下一轮，不会丢失。</p>
 */
@Component
public class OutboxRelayJob {

    private static final Logger log = LoggerFactory.getLogger(OutboxRelayJob.class);

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final OutboxEventDao outboxDao;
    private final DomainEventPublisher publisher;

    @Value("${takeout.mq.outbox-batch-size:100}")
    private int batchSize = 100;

    @Value("${takeout.mq.max-retry:10}")
    private int maxRetry = 10;

    /** 已投递事件的保留时长（小时），用于定期清理。 */
    @Value("${takeout.mq.retain-hours:72}")
    private int retainHours = 72;

    public OutboxRelayJob(OutboxEventDao outboxDao, DomainEventPublisher publisher) {
        this.outboxDao = outboxDao;
        this.publisher = publisher;
    }

    @Scheduled(fixedDelayString = "${takeout.mq.relay-scan-ms:2000}",
            initialDelayString = "${takeout.mq.relay-initial-ms:10000}")
    public void relay() {
        if (!publisher.isEnabled()) {
            return;
        }
        try {
            List<OutboxEventDao.OutboxEvent> pending = outboxDao.listPending(batchSize);
            // ponytail: listPending 用 SELECT ... WHERE status=0 无行级锁，多实例会重复投递同一事件。
            // 消费端 setIfAbsent 去重保证不会重复处理，故仅为轻微浪费（Stream 多存一份副本）。
            // 真正多实例生产环境应改为 SELECT ... FOR UPDATE SKIP LOCKED + 事务内 claim。
            if (pending.isEmpty()) {
                return;
            }
            int sent = 0;
            int retried = 0;
            for (OutboxEventDao.OutboxEvent event : pending) {
                // 事件已持久化在数据库中，重试几乎零成本；
                // 因此这里【永不放弃】投递，只统计重试次数用于告警。
                // 若因重试上限而跳过，Redis 的短暂故障就会变成事件的永久丢失（实测踩过）。
                if (publisher.deliver(event.id(), event.eventType(), event.orderId(), event.payload())) {
                    outboxDao.markSent(event.id());
                    sent++;
                } else {
                    outboxDao.markRetry(event.id());
                    retried++;
                }
            }
            if (sent > 0) {
                log.info("[Outbox] 投递完成 sent={} retried={} pendingBefore={}", sent, retried, pending.size());
            }
            // 重试次数偏高说明 Redis 长期不可用，需要运维介入
            if (retried > 0 && outboxDao.countExhausted(maxRetry) > 0) {
                log.warn("[Outbox] 存在重试超过 {} 次仍未投递成功的事件 count={}，请检查 Redis 可用性",
                        maxRetry, outboxDao.countExhausted(maxRetry));
            }
        } catch (Exception e) {
            // 定时任务异常不得中断调度
            log.warn("[Outbox] 中继扫描失败", e);
        }
    }

    /** 清理已投递的历史事件，避免 outbox 表无限增长。 */
    @Scheduled(fixedDelayString = "${takeout.mq.cleanup-scan-ms:3600000}",
            initialDelayString = "${takeout.mq.cleanup-initial-ms:60000}")
    public void cleanup() {
        try {
            String threshold = LocalDateTime.now().minusHours(Math.max(retainHours, 1)).format(FMT);
            int deleted = outboxDao.deleteSentBefore(threshold);
            if (deleted > 0) {
                log.info("[Outbox] 清理已投递事件 count={}", deleted);
            }
            int exhausted = outboxDao.countExhausted(maxRetry);
            if (exhausted > 0) {
                log.warn("[Outbox] 存在重试超过 {} 次仍未成功的事件 count={}，请检查 Redis 与消费端", maxRetry, exhausted);
            }
        } catch (Exception e) {
            log.warn("[Outbox] 清理失败", e);
        }
    }
}
