package com.example.takeout.job;

import com.example.takeout.common.InstanceId;
import com.example.takeout.common.SchedulerLock;
import com.example.takeout.dao.OutboxEventDao;
import com.example.takeout.service.mq.DomainEventPublisher;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
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
 * <p><b>多实例</b>：通过 {@link OutboxEventDao#claimPending} 的
 * {@code FOR UPDATE SKIP LOCKED} 行级认领，同一事件只会被一个实例搬运；
 * 认领后崩溃的行在租约过期后由其他实例接手，不会永久滞留。</p>
 *
 * <p>Redis 不可用时事件保留在表中等待下一轮，不会丢失。</p>
 */
@Component
public class OutboxRelayJob {

    private static final Logger log = LoggerFactory.getLogger(OutboxRelayJob.class);

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final OutboxEventDao outboxDao;
    private final DomainEventPublisher publisher;
    private final SchedulerLock schedulerLock;

    @Value("${takeout.mq.outbox-batch-size:100}")
    private int batchSize = 100;

    @Value("${takeout.mq.max-retry:10}")
    private int maxRetry = 10;

    /** 已投递事件的保留时长（小时），用于定期清理。 */
    @Value("${takeout.mq.retain-hours:72}")
    private int retainHours = 72;

    /**
     * 认领租约时长（毫秒）。
     *
     * <p>语义：认领后若实例崩溃，该行要等租约过期才能被其他实例接手。
     * 因此取值要显著大于「投递一批事件的耗时」，又不能长到让崩溃事件长时间滞留。
     * 默认 30 秒，远大于本机实测的单批投递耗时（毫秒级）。</p>
     */
    @Value("${takeout.mq.claim-lease-ms:30000}")
    private long claimLeaseMs = 30000;

    /** 调度锁 TTL（毫秒）：仅 cleanup 使用，略大于单轮清理耗时。 */
    @Value("${takeout.job.cleanup-lock-ttl-ms:300000}")
    private long lockTtlMs = 300000;

    public OutboxRelayJob(OutboxEventDao outboxDao, DomainEventPublisher publisher, SchedulerLock schedulerLock) {
        this.outboxDao = outboxDao;
        this.publisher = publisher;
        this.schedulerLock = schedulerLock;
    }

    @Scheduled(fixedDelayString = "${takeout.mq.relay-scan-ms:2000}",
            initialDelayString = "${takeout.mq.relay-initial-ms:10000}")
    public void relay() {
        if (!publisher.isEnabled()) {
            return;
        }
        try {
            long now = System.currentTimeMillis();
            String owner = InstanceId.current();
            // 行级认领：事务内 SELECT ... FOR UPDATE SKIP LOCKED 并盖认领戳。
            // 多实例下同一事件只会出现在一个实例的返回结果里，从根上消除重复搬运。
            List<OutboxEventDao.OutboxEvent> pending = outboxDao.claimPending(batchSize, owner, now, now + claimLeaseMs);
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
                    // markRetry 同时释放租约，让其他健康实例立刻能接手重试
                    outboxDao.markRetry(event.id());
                    retried++;
                }
            }
            if (sent > 0) {
                log.info("[Outbox] 投递完成 sent={} retried={} claimed={} owner={}",
                        sent, retried, pending.size(), owner);
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

    /**
     * 清理已投递的历史事件，避免 outbox 表无限增长。
     *
     * <p><b>为什么这里加调度锁，而 relay() 不加</b>：relay() 已用行级认领
     * （{@code FOR UPDATE SKIP LOCKED}），多实例并行搬运是我们要的吞吐；给它加锁反而会
     * 把多实例退化成单实例。cleanup() 是全表 DELETE，多实例同时跑只是重复做同一件无用功，
     * 加锁消除浪费即可（DELETE 本身幂等，锁不可用时放行无正确性风险）。</p>
     */
    @Scheduled(fixedDelayString = "${takeout.mq.cleanup-scan-ms:3600000}",
            initialDelayString = "${takeout.mq.cleanup-initial-ms:60000}")
    public void cleanup() {
        try {
            schedulerLock.tryRun("outbox-cleanup", Duration.ofMillis(Math.max(lockTtlMs, 1)), () -> {
                String threshold = LocalDateTime.now().minusHours(Math.max(retainHours, 1)).format(FMT);
                int deleted = outboxDao.deleteSentBefore(threshold);
                if (deleted > 0) {
                    log.info("[Outbox] 清理已投递事件 count={}", deleted);
                }
                int exhausted = outboxDao.countExhausted(maxRetry);
                if (exhausted > 0) {
                    log.warn("[Outbox] 存在重试超过 {} 次仍未成功的事件 count={}，请检查 Redis 与消费端", maxRetry, exhausted);
                }
            });
        } catch (Exception e) {
            log.warn("[Outbox] 清理失败", e);
        }
    }
}
