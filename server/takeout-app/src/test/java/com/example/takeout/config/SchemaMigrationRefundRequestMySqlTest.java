package com.example.takeout.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class SchemaMigrationRefundRequestMySqlTest {
    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private String database;

    @BeforeEach
    void setUp() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1")
                + ":" + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        database = "takeout_refund_migrate_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        jdbc = new JdbcTemplate(new DriverManagerDataSource(base + database + options, username, password));
        jdbc.execute("CREATE TABLE refund_records (id BIGINT AUTO_INCREMENT PRIMARY KEY, order_id BIGINT NOT NULL) " +
                "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
        jdbc.update("INSERT INTO refund_records(order_id) VALUES(7),(7)");
    }

    @AfterEach
    void cleanUp() {
        if (admin != null && database != null) admin.execute("DROP DATABASE IF EXISTS `" + database + "`");
    }

    @Test
    void migrationPreservesLegacyRowsAllowsNullAndEnforcesCaseSensitiveRequestIdentity() {
        SchemaMigration migration = new SchemaMigration(jdbc);
        migration.migrateRefundRequests();
        migration.migrateRefundRequests();
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.COLUMNS " +
                "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='refund_records' AND COLUMN_NAME='request_key' " +
                "AND IS_NULLABLE='YES' AND COLLATION_NAME='utf8mb4_0900_bin'", Integer.class));
        assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM refund_records WHERE request_key IS NULL", Integer.class));
        jdbc.update("INSERT INTO refund_records(order_id,request_key) VALUES(7,'Refund-A'),(7,'refund-a'),(8,'Refund-A')");
        assertThrows(DuplicateKeyException.class,
                () -> jdbc.update("INSERT INTO refund_records(order_id,request_key) VALUES(7,'Refund-A')"));
        jdbc.update("INSERT INTO refund_apply_requests(order_id,request_key,refund_id) VALUES " +
                "(7,'Alias-A',1),(7,'alias-a',1),(8,'Alias-A',2)");
        assertThrows(DuplicateKeyException.class, () -> jdbc.update("INSERT INTO refund_apply_requests " +
                "(order_id,request_key,refund_id) VALUES(7,'Alias-A',2)"));
        migration.migrateRefundRequests();
        assertEquals(1, jdbc.queryForObject("SELECT refund_id FROM refund_apply_requests " +
                "WHERE order_id=7 AND request_key='Alias-A'", Integer.class));
    }
}
