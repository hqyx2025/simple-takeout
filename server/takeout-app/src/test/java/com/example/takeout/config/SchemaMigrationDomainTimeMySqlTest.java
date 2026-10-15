package com.example.takeout.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class SchemaMigrationDomainTimeMySqlTest {

    private static final Map<String, List<String>> TIME_COLUMNS = Map.of(
            "coupons", List.of("expire_time", "create_time"),
            "user_coupons", List.of("claim_time", "expire_time"),
            "marketing_activities", List.of("start_time", "end_time", "create_time"),
            "seckills", List.of("start_time", "end_time", "create_time"),
            "seckill_orders", List.of("create_time"),
            "outbox_events", List.of("create_time"));

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
        database = "takeout_domain_migration_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        var source = new DriverManagerDataSource(base + database + options, username, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);

        for (var table : TIME_COLUMNS.entrySet()) {
            for (String column : table.getValue()) {
                Integer exists = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.COLUMNS " +
                                "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
                        Integer.class, table.getKey(), column + "_dt");
                if (exists != null && exists > 0) {
                    jdbc.execute("ALTER TABLE " + table.getKey() + " DROP COLUMN " + column + "_dt");
                }
            }
        }
        jdbc.update("INSERT INTO coupons(id,user_id,name,expire_time,create_time) " +
                "VALUES(1,7,'legacy coupon','','2026-10-14 09:00:00')");
        jdbc.update("INSERT INTO user_coupons(id,user_id,name,claim_time,expire_time) " +
                "VALUES(1,7,'legacy claim','2026-10-14 09:00:00','')");
        jdbc.update("INSERT INTO marketing_activities(id,store_id,type,title,start_time,end_time,create_time) " +
                "VALUES(1,10,'DISCOUNT','legacy activity','2026-10-14 10:00:00','2026-10-14 13:00:00','2026-10-14 09:00:00')");
        jdbc.update("INSERT INTO seckills(id,goods_id,store_id,start_time,end_time,create_time) " +
                "VALUES(1,100,10,'2026-10-14 10:00:00','2026-10-14 13:00:00','2026-10-14 09:00:00')");
        jdbc.update("INSERT INTO seckill_orders(id,user_id,seckill_id,create_time) " +
                "VALUES(1,7,1,'2026-10-14 11:00:00')");
        jdbc.update("INSERT INTO outbox_events(id,event_type,create_time) " +
                "VALUES(1,'ORDER_CREATED','legacy-invalid-time')");
    }

    @AfterEach
    void cleanUp() {
        if (database != null) {
            admin.execute("DROP DATABASE `" + database + "`");
        }
    }

    @Test
    void addsNullableDomainDatetimeColumnsIdempotentlyWithoutRewritingLegacyData() {
        Map<String, String> original = new LinkedHashMap<>();
        TIME_COLUMNS.forEach((table, columns) -> columns.forEach(column -> original.put(table + "." + column,
                jdbc.queryForObject("SELECT " + column + " FROM " + table + " WHERE id = 1", String.class))));
        SchemaMigration migration = new SchemaMigration(jdbc);

        migration.migrateDomainTimeColumns();
        migration.migrateDomainTimeColumns();

        int verifiedColumns = 0;
        for (var table : TIME_COLUMNS.entrySet()) {
            for (String column : table.getValue()) {
                var metadata = jdbc.queryForMap("SELECT DATA_TYPE, IS_NULLABLE FROM information_schema.COLUMNS " +
                                "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
                        table.getKey(), column + "_dt");
                assertEquals("datetime", metadata.get("DATA_TYPE"));
                assertEquals("YES", metadata.get("IS_NULLABLE"));
                assertEquals(original.get(table.getKey() + "." + column), jdbc.queryForObject(
                        "SELECT " + column + " FROM " + table.getKey() + " WHERE id = 1", String.class));
                assertNull(jdbc.queryForObject("SELECT " + column + "_dt FROM " + table.getKey() + " WHERE id = 1",
                        Object.class));
                verifiedColumns++;
            }
        }
        assertEquals(12, verifiedColumns);
    }
}
