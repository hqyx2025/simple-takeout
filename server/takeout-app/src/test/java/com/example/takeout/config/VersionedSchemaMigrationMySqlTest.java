package com.example.takeout.config;

import com.example.takeout.TakeoutApplication;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.exception.FlywayValidateException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

import static org.junit.jupiter.api.Assertions.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class VersionedSchemaMigrationMySqlTest {
    @Test void oldDatabaseUpgradesBeforeBaselineAndRepeatedStartupPreservesDataAndChecksumProtection() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1") + ":"
                + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        var admin = new JdbcTemplate(new DriverManagerDataSource(base + options, user, password));
        String schema = "takeout_versioned_" + java.util.UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + schema + "`");
        try {
            var source = new DriverManagerDataSource(base + schema + options, user, password);
            new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
            var db = new JdbcTemplate(source);
            // A pre-upgrade fixture, exclusively in this disposable database.
            db.execute("ALTER TABLE orders DROP COLUMN reject_spec_id");
            db.execute("ALTER TABLE order_create_requests DROP COLUMN order_id");
            db.execute("ALTER TABLE stores DROP COLUMN rating_count");
            db.update("INSERT INTO stores(id,name,owner_id,rating,create_time) VALUES"
                    + "(1,'rated',1,4.9,'2026-01-01'),(2,'unrated',1,4.9,'2026-01-01')");
            db.update("INSERT INTO reviews(store_id,order_id,goods_id,user_id,user_name,rating,create_time) VALUES"
                    + "(1,1,1,1,'A',5,'2026-01-01'),(1,1,2,1,'A',5,'2026-01-01'),"
                    + "(1,1,3,1,'A',5,'2026-01-01'),(1,2,1,2,'B',1,'2026-01-01'),"
                    + "(1,3,1,3,'Invalid',0,'2026-01-01')");
            db.update("INSERT INTO users(id,username,phone,password,balance,create_time) "
                    + "VALUES(123,'migration-sentinel','13800000999','unused',123.45,'2026-01-01 00:00:00')");
            String personalKey=key(), indexKey=key();
            for (int start = 0; start < 2; start++) {
                try (var context = new SpringApplicationBuilder(TakeoutApplication.class).run(
                        "--spring.main.web-application-type=none", "--spring.profiles.active=test",
                        "--spring.datasource.url=" + base + schema + options, "--spring.datasource.username=" + user,
                        "--spring.datasource.password=" + password, "--spring.datasource.hikari.maximum-pool-size=2",
                        "--spring.datasource.hikari.minimum-idle=0", "--takeout.jwt.secret=" + key(),
                        "--takeout.sms.hmac-secret=" + key(), "--takeout.assistant.encryption-secret=" + key(),
                        "--takeout.wallet.encryption-secret=" + key(), "--takeout.erp.integration-secret=" + key(),
                        "--takeout.personal-data.encryption-secret=" + personalKey, "--takeout.personal-data.index-secret=" + indexKey,
                        "--takeout.payment.sandbox=false", "--takeout.payment.real-enabled=false",
                        "--takeout.sms.qq.smtp-host=127.0.0.1", "--takeout.sms.qq.smtp-port=1",
                        "--takeout.sms.qq.username=isolated-test@example.invalid", "--takeout.sms.qq.auth-code=local-test-only",
                        "--takeout.data-seed.enabled=false", "--takeout.mq.enabled=false", "--takeout.cache.enabled=false",
                        "--spring.data.redis.lettuce.pool.min-idle=0")) {
                    assertEquals(123.45, db.queryForObject("SELECT balance FROM users WHERE id=123", Double.class), 0.001);
                    assertEquals(1, db.queryForObject("SELECT COUNT(*) FROM flyway_schema_history WHERE version='1' AND success=1", Integer.class));
                    assertEquals(0, db.queryForList("SELECT reject_spec_id FROM orders").size());
                    assertEquals(3.0, db.queryForObject("SELECT rating FROM stores WHERE id=1", Double.class));
                    assertEquals(2, db.queryForObject("SELECT rating_count FROM stores WHERE id=1", Integer.class));
                    assertEquals(0, db.queryForObject("SELECT rating_count FROM stores WHERE id=2", Integer.class));
                    assertEquals(0.0, db.queryForObject("SELECT rating FROM stores WHERE id=2", Double.class));
                    context.getBean(com.example.takeout.dao.StoreDao.class).updateRatingFromReviews(1);
                    assertEquals(3.0, db.queryForObject("SELECT rating FROM stores WHERE id=1", Double.class));
                    assertEquals(2, db.queryForObject("SELECT rating_count FROM stores WHERE id=1", Integer.class));
                    context.getBean(Flyway.class).validate();
                    if (start == 1) {
                        db.update("UPDATE flyway_schema_history SET checksum=checksum+1 WHERE version='1'");
                        assertThrows(FlywayValidateException.class, () -> context.getBean(Flyway.class).validate());
                    }
                }
            }
        } finally { admin.execute("DROP DATABASE `" + schema + "`"); }
    }

    private String key() {
        byte[] bytes = new byte[32];
        new java.security.SecureRandom().nextBytes(bytes);
        return java.util.Base64.getEncoder().encodeToString(bytes);
    }
}
