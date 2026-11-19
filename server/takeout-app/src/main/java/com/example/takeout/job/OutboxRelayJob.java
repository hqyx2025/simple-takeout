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
 * Outbox 中继：把数据库里待投递的领域事件搬运到 RocketMQ。
 *
 * <p>投递采用「至少一次」语义：投递成功即置 status=1。
 * 若在投递成功后、置位前崩溃，事件会被重复投递，因此
 * 消费端必须按 eventId 做幂等（见 {@link com.example.takeout.service.mq.DomainEventConsumer}）。</p>
 *
 * <p><b>多实例</b>：通过 {@link OutboxEventDao#claimPending} 的
 * {@code FOR UPDATE SKIP LOCKED} 行级认领，同一事件只会被一个实例搬运；
 * 认领后崩溃的行在租约过期后由其他实例接手，不会永久滞留。</p>
 *
 * <p>RocketMQ 不可用时事件保留在表中等待下一轮，不会丢失。</p>
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

    // Four bounded workers; each claims only the next small batch it can actually process.
    private final java.util.concurrent.ExecutorService workers = java.util.concurrent.Executors.newFixedThreadPool(4,
            Thread.ofPlatform().name("outbox-delivery-", 0).factory());
    @Value("${takeout.mq.relay-budget-ms:1000}")
    private long budgetMs = 1000;

    @jakarta.annotation.PreDestroy
    public void close() {
        workers.shutdown();
        try { if (!workers.awaitTermination(15, java.util.concurrent.TimeUnit.SECONDS)) workers.shutdownNow(); }
        catch (InterruptedException e) { workers.shutdownNow(); Thread.currentThread().interrupt(); }
    }

    @Scheduled(scheduler = "outboxScheduler", fixedDelayString = "${takeout.mq.relay-scan-ms:100}",
            initialDelayString = "${takeout.mq.relay-initial-ms:10000}")
    public void relay() {
        if (!publisher.isEnabled()) return;
        long deadline = System.nanoTime() + java.util.concurrent.TimeUnit.MILLISECONDS.toNanos(Math.clamp(budgetMs, 100, 5000));
        var remaining = new java.util.concurrent.atomic.AtomicInteger(Math.clamp(batchSize, 1, 2000));
        var futures = new java.util.ArrayList<java.util.concurrent.Future<?>>();
        for (int i = 0; i < 4; i++) futures.add(workers.submit(() -> drain(deadline, remaining)));
        for (var future : futures) {
            try { future.get(); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); return; }
            catch (java.util.concurrent.ExecutionException e) { log.warn("[Outbox] 中继工作失败", e.getCause()); }
        }
    }

    private void drain(long deadline, java.util.concurrent.atomic.AtomicInteger remaining) {
        String owner = java.util.UUID.randomUUID().toString();
        while (!Thread.currentThread().isInterrupted() && System.nanoTime() < deadline) {
            int reserved = remaining.getAndUpdate(value -> Math.max(0, value - 5));
            if (reserved <= 0) return;
            long now = System.currentTimeMillis();
            List<OutboxEventDao.OutboxEvent> pending = outboxDao.claimPending(Math.min(reserved, 5), owner, now,
                    now + Math.max(claimLeaseMs, 105000));
            if (pending.isEmpty()) return;
            for (var event : pending) {
                try {
                    if (publisher.deliver(event.id(), event.eventType(), event.orderId(), event.payload())) {
                        outboxDao.markSent(event.id(), owner);
                    } else outboxDao.markRetry(event.id(), owner, event.retryCount());
                } catch (RuntimeException failure) {
                    log.warn("[Outbox] 投递失败 eventId={}，保留租约恢复", event.id(), failure);
                    try { outboxDao.markRetry(event.id(), owner, event.retryCount()); }
                    catch (RuntimeException ignored) { /* The durable lease permits recovery after expiry. */ }
                }
            }
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
                    log.warn("[Outbox] 存在重试超过 {} 次仍未成功的事件 count={}，请检查 RocketMQ 与消费端", maxRetry, exhausted);
                }
            });
        } catch (Exception e) {
            log.warn("[Outbox] 清理失败", e);
        }
    }
}
