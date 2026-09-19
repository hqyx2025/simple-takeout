package com.example.takeout.job;

import com.example.takeout.common.SchedulerLock;
import com.example.takeout.service.OrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;

/**
 * 待付款订单超时自动取消（演进项 10.6）。
 * 默认每分钟扫描一次 status=0 且创建时间超过支付时限的订单，取消并回滚库存、秒杀名额与优惠券。
 * 支付时限由 takeout.order.pay-timeout-minutes 配置（默认 15 分钟）。
 *
 * <p><b>多实例</b>：扫描间隔（默认 60 秒）远小于支付时限（默认 15 分钟），
 * 多实例同时扫描会让同一批超时订单被反复读库。取消动作本身已是条件更新
 * （{@code WHERE id = ? AND status = 0}）不会重复退款，故这里加调度锁只为消除无谓扫描，
 * 且 Redis 不可用时放行（fail-open）——绝不能因一把锁让超时订单不再自动取消。</p>
 */
@Component
public class OrderTimeoutJob {

    private static final Logger log = LoggerFactory.getLogger(OrderTimeoutJob.class);

    private static final String JOB_NAME = "order-timeout-scan";

    private final OrderService orderService;
    private final SchedulerLock schedulerLock;

    /** 调度锁 TTL（毫秒）：略大于单轮扫描耗时，避免实例崩溃后死锁。 */
    @Value("${takeout.job.timeout-lock-ttl-ms:120000}")
    private long lockTtlMs = 120000;

    public OrderTimeoutJob(OrderService orderService, SchedulerLock schedulerLock) {
        this.orderService = orderService;
        this.schedulerLock = schedulerLock;
    }

    @Scheduled(fixedDelayString = "${takeout.order.timeout-scan-ms:60000}",
            initialDelayString = "${takeout.order.timeout-scan-initial-ms:30000}")
    public void cancelExpiredPendingOrders() {
        try {
            schedulerLock.tryRun(JOB_NAME, Duration.ofMillis(Math.max(lockTtlMs, 1)), () -> {
                int cancelled = orderService.cancelExpiredPendingOrders();
                if (cancelled > 0) {
                    log.info("[超时取消] 自动取消待付款订单 count={}", cancelled);
                }
            });
        } catch (Exception e) {
            // 定时任务异常不得中断后续调度
            log.warn("[超时取消] 扫描失败", e);
        }
    }
}
