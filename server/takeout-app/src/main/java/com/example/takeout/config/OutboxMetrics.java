package com.example.takeout.config;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** One bounded aggregate per refresh; scrapes never query the business database. */
@Component
public class OutboxMetrics {
    private static final Logger log = LoggerFactory.getLogger(OutboxMetrics.class);
    private final JdbcTemplate jdbc;
    private volatile Snapshot snapshot = new Snapshot(Double.NaN, Double.NaN, Double.NaN, 0);
    private record Snapshot(double pending, double maxRetries, double oldestSeconds, double available) {}

    public OutboxMetrics(JdbcTemplate jdbc, MeterRegistry registry) {
        this.jdbc = jdbc;
        Gauge.builder("takeout.outbox.pending", this, metrics -> metrics.snapshot.pending()).register(registry);
        Gauge.builder("takeout.outbox.max.retries", this, metrics -> metrics.snapshot.maxRetries()).register(registry);
        Gauge.builder("takeout.outbox.oldest.age.seconds", this, metrics -> metrics.snapshot.oldestSeconds()).register(registry);
        Gauge.builder("takeout.outbox.collector.available", this, metrics -> metrics.snapshot.available()).register(registry);
    }

    @Scheduled(fixedDelayString = "${takeout.observability.outbox-refresh-ms:15000}", initialDelay = 15000)
    public void refresh() {
        try {
            snapshot = jdbc.queryForObject("SELECT COUNT(*) pending, COALESCE(MAX(retry_count),0) retries, "
                    + "GREATEST(COALESCE(TIMESTAMPDIFF(SECOND,MIN(create_time_dt),CURRENT_TIMESTAMP),0),0) age "
                    + "FROM outbox_events WHERE status=0",
                    (row, index) -> new Snapshot(row.getDouble("pending"), row.getDouble("retries"), row.getDouble("age"), 1));
        } catch (org.springframework.dao.DataAccessException failure) {
            snapshot = new Snapshot(Double.NaN, Double.NaN, Double.NaN, 0);
            log.warn("[Outbox指标] 采集失败，标记为不可用，不能据此认定积压为零");
        }
    }
}
