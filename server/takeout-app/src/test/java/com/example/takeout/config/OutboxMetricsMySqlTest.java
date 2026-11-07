package com.example.takeout.config;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

import static org.junit.jupiter.api.Assertions.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class OutboxMetricsMySqlTest {
    @Test void reportsOnlyPendingEventsAndKeepsDatabaseCollectionFailureDistinctFromZeroBacklog() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1") + ":"
                + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        var admin = new JdbcTemplate(new DriverManagerDataSource(base + options, user, password));
        String schema = "takeout_metrics_" + java.util.UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + schema + "`");
        var registry = new SimpleMeterRegistry();
        try {
            var source = new DriverManagerDataSource(base + schema + options, user, password);
            new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
            var db = new JdbcTemplate(source);
            db.update("INSERT INTO outbox_events(event_type,order_id,payload,status,retry_count,create_time,create_time_dt) "
                    + "VALUES('ORDER_CREATED',1,'{}',0,3,'2026-01-01 00:00:00',DATE_SUB(NOW(),INTERVAL 30 MINUTE)),"
                    + "('ORDER_PAID',2,'{}',1,99,'2026-01-01 00:00:00',DATE_SUB(NOW(),INTERVAL 1 DAY))");
            var metrics = new OutboxMetrics(db, registry);
            metrics.refresh();
            assertEquals(1, registry.get("takeout.outbox.pending").gauge().value());
            assertEquals(3, registry.get("takeout.outbox.max.retries").gauge().value());
            assertTrue(registry.get("takeout.outbox.oldest.age.seconds").gauge().value() >= 1800);
            assertEquals(1, registry.get("takeout.outbox.collector.available").gauge().value());
            db.execute("DROP TABLE outbox_events"); // Isolated schema fault injection, not a real database shutdown.
            metrics.refresh();
            assertEquals(0, registry.get("takeout.outbox.collector.available").gauge().value());
            assertTrue(Double.isNaN(registry.get("takeout.outbox.pending").gauge().value()));
        } finally { registry.close(); admin.execute("DROP DATABASE `" + schema + "`"); }
    }
}
