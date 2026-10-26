package com.example.takeout.config;

import com.example.takeout.dao.AddressDao;
import com.example.takeout.model.Address;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Opt-in real MySQL regression. It creates and drops only a random temporary database.
 */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class SchemaMigrationAddressMySqlTest {

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
        database = "takeout_address_migration_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");

        var source = new DriverManagerDataSource(base + database + options, username, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        jdbc.execute("DROP TABLE addresses");
        jdbc.execute("CREATE TABLE addresses (" +
                "id BIGINT AUTO_INCREMENT PRIMARY KEY," +
                "user_id BIGINT NOT NULL," +
                "name VARCHAR(64) NOT NULL," +
                "phone VARCHAR(20) NOT NULL," +
                "detail VARCHAR(255) NOT NULL," +
                "is_default INT NOT NULL DEFAULT 0," +
                "latitude DECIMAL(10,7) DEFAULT NULL," +
                "longitude DECIMAL(10,7) DEFAULT NULL," +
                "create_time VARCHAR(32) NOT NULL" +
                ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    }

    @AfterEach
    void cleanUp() {
        if (admin != null && database != null) {
            admin.execute("DROP DATABASE IF EXISTS `" + database + "`");
        }
    }

    @Test
    void migratesLegacyAddressColumnsIdempotentlyAndRoundTripsStructuredAddress() {
        jdbc.update("INSERT INTO addresses(user_id,name,phone,detail,is_default,create_time) " +
                "VALUES(40,'旧用户','13900139000','旧地址',0,'2026-10-26 14:00:00')");
        SchemaMigration migration = new SchemaMigration(jdbc);

        migration.run(null);
        migration.run(null);

        Integer structuredColumns = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.COLUMNS " +
                        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'addresses' " +
                        "AND COLUMN_NAME IN ('map_address', 'door_detail', 'tag')",
                Integer.class);
        assertEquals(3, structuredColumns);

        AddressDao dao = new AddressDao(jdbc);
        assertEquals("", dao.listByUser(40).getFirst().tag());
        long id = dao.insert(41, "张女士", "13800138000", "南宁学院东门 3栋1206", 1,
                22.8167000, 108.3200000, "南宁学院东门", "3栋1206", "学校",
                "2026-10-26 15:00:00");
        List<Address> addresses = dao.listByUser(41);

        assertEquals(1, addresses.size());
        Address saved = addresses.getFirst();
        assertEquals(id, saved.id());
        assertEquals("南宁学院东门 3栋1206", saved.detail());
        assertEquals("南宁学院东门", saved.mapAddress());
        assertEquals("3栋1206", saved.doorDetail());
        assertEquals("学校", saved.tag());
        assertEquals(22.8167000, saved.latitude(), 0.0000001);
        assertEquals(108.3200000, saved.longitude(), 0.0000001);
        assertEquals(1, saved.isDefault());
    }
}
