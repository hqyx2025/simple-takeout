package com.example.takeout.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class SchemaMigrationOrderTimeMySqlTest {

    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private String database;

    @BeforeEach
    void setUp() {
        String host = System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1");
        String port = System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310");
        String base = "jdbc:mysql://" + host + ":" + port + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        database = "takeout_order_time_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        jdbc = new JdbcTemplate(new DriverManagerDataSource(base + database + options, username, password));
        jdbc.execute("CREATE TABLE orders (id BIGINT PRIMARY KEY, create_time VARCHAR(32), pay_time VARCHAR(32), " +
                "accept_time VARCHAR(32), deliver_time VARCHAR(32), complete_time VARCHAR(32), ready_time VARCHAR(32), " +
                "expect_time VARCHAR(32)) ENGINE=InnoDB");
        jdbc.update("INSERT INTO orders VALUES(1,?,?,?,?,?,?,?)", "2026-10-14 09:00:00", "", "", "", "", "", "");
    }

    @AfterEach
    void cleanUp() {
        if (database != null) {
            admin.execute("DROP DATABASE `" + database + "`");
        }
    }

    @Test
    void addsNullableDatetimeShadowsIdempotentlyAndPreservesLegacyValues() {
        SchemaMigration migration = new SchemaMigration(jdbc);

        migration.migrateOrderTimeColumns();
        migration.migrateOrderTimeColumns();

        Integer shadowColumns = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.COLUMNS " +
                        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders' AND RIGHT(COLUMN_NAME, 3) = '_dt'",
                Integer.class);
        assertEquals(7, shadowColumns);
        assertEquals("2026-10-14 09:00:00", jdbc.queryForObject(
                "SELECT create_time FROM orders WHERE id = 1", String.class));
        assertEquals("datetime", jdbc.queryForObject("SELECT DATA_TYPE FROM information_schema.COLUMNS " +
                "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders' AND COLUMN_NAME = 'create_time_dt'",
                String.class));
    }
}
