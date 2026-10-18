package com.example.takeout.job;

import com.example.takeout.common.SchedulerLock;
import com.example.takeout.service.OrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;

@Component
public class OrderAutoConfirmJob {

    private static final Logger log = LoggerFactory.getLogger(OrderAutoConfirmJob.class);
    private final OrderService orderService;
    private final SchedulerLock schedulerLock;

    @Value("${takeout.order.auto-confirm-hours:24}")
    private int autoConfirmHours = 24;

    public OrderAutoConfirmJob(OrderService orderService, SchedulerLock schedulerLock) {
        this.orderService = orderService;
        this.schedulerLock = schedulerLock;
    }

    @Scheduled(fixedDelayString = "${takeout.order.auto-confirm-scan-ms:60000}",
            initialDelayString = "${takeout.order.auto-confirm-scan-initial-ms:45000}")
    public void settleDeliveredOrders() {
        try {
            schedulerLock.tryRun("order-auto-confirm", Duration.ofMinutes(5), () -> {
                int count = orderService.autoConfirmDeliveredOrders(Math.max(autoConfirmHours, 1));
                if (count > 0) log.info("[自动确认收货] 自动结算订单 count={}", count);
            });
        } catch (Exception e) {
            log.warn("[自动确认收货] 扫描失败", e);
        }
    }
}
