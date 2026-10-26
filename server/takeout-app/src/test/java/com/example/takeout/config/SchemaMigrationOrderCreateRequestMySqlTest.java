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
class SchemaMigrationOrderCreateRequestMySqlTest {

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
        database = "takeout_order_request_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        jdbc = new JdbcTemplate(new DriverManagerDataSource(base + database + options, username, password));
        jdbc.execute("CREATE TABLE order_create_requests (user_id BIGINT NOT NULL, request_key VARCHAR(128) NOT NULL, " +
                "create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(user_id, request_key)) ENGINE=InnoDB");
    }

    @AfterEach
    void cleanUp() {
        if (admin != null && database != null) admin.execute("DROP DATABASE IF EXISTS `" + database + "`");
    }

    @Test
    void addsNullableOrderMappingIdempotently() {
        SchemaMigration migration = new SchemaMigration(jdbc);

        migration.migrateOrderCreateRequests();
        migration.migrateOrderCreateRequests();

        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.COLUMNS " +
                "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='order_create_requests' AND COLUMN_NAME='order_id' " +
                "AND IS_NULLABLE='YES'", Integer.class));
    }
}
