package com.example.takeout.job;

import com.example.takeout.service.OrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 待付款订单超时自动取消（演进项 10.6）。
 * 默认每分钟扫描一次 status=0 且创建时间超过支付时限的订单，取消并回滚库存、秒杀名额与优惠券。
 * 支付时限由 takeout.order.pay-timeout-minutes 配置（默认 15 分钟）。
 */
@Component
public class OrderTimeoutJob {

    private static final Logger log = LoggerFactory.getLogger(OrderTimeoutJob.class);

    private final OrderService orderService;

    public OrderTimeoutJob(OrderService orderService) {
        this.orderService = orderService;
    }

    @Scheduled(fixedDelayString = "${takeout.order.timeout-scan-ms:60000}",
            initialDelayString = "${takeout.order.timeout-scan-initial-ms:30000}")
    public void cancelExpiredPendingOrders() {
        try {
            int cancelled = orderService.cancelExpiredPendingOrders();
            if (cancelled > 0) {
                log.info("[超时取消] 自动取消待付款订单 count={}", cancelled);
            }
        } catch (Exception e) {
            // 定时任务异常不得中断后续调度
            log.warn("[超时取消] 扫描失败", e);
        }
    }
}
