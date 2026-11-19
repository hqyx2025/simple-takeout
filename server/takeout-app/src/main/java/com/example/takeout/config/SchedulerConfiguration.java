package com.example.takeout.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/** A slow channel or broker cannot stop order expiry, metrics, or housekeeping. */
@Configuration
public class SchedulerConfiguration {
    @Bean public ThreadPoolTaskScheduler taskScheduler() { return scheduler("housekeeping-", 2); }
    @Bean public ThreadPoolTaskScheduler orderScheduler() { return scheduler("order-recovery-", 2); }
    @Bean public ThreadPoolTaskScheduler paymentRecoveryScheduler() { return scheduler("payment-recovery-", 2); }
    @Bean public ThreadPoolTaskScheduler outboxScheduler() { return scheduler("outbox-relay-", 1); }

    private ThreadPoolTaskScheduler scheduler(String prefix, int size) {
        var scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(size);
        scheduler.setThreadNamePrefix(prefix);
        scheduler.setRemoveOnCancelPolicy(true);
        scheduler.setWaitForTasksToCompleteOnShutdown(true);
        scheduler.setAwaitTerminationSeconds(15);
        return scheduler;
    }
}
