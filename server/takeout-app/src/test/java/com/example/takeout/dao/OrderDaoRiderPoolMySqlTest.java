package com.example.takeout.dao;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Opt-in real MySQL check that legacy pickup rows never enter rider dispatch. */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class OrderDaoRiderPoolMySqlTest {

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
        database = "takeout_rider_pool_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        var source = new DriverManagerDataSource(base + database + options, username, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        insertReadyOrder(1, "DELIVERY");
        insertReadyOrder(2, "PICKUP");
    }

    @AfterEach
    void cleanUp() {
        if (admin != null && database != null) {
            admin.execute("DROP DATABASE IF EXISTS `" + database + "`");
        }
    }

    @Test
    void pickupRowsCannotEnterPoolOrBeClaimed() {
        OrderDao dao = new OrderDao(jdbc);

        assertEquals(1, dao.listRiderPool().size());
        assertEquals(1, dao.listRiderPool().getFirst().id());
        assertFalse(dao.tryAssignRider(2, 77));
        assertEquals(0, jdbc.queryForObject("SELECT rider_id FROM orders WHERE id=2", Integer.class));
        assertTrue(dao.tryAssignRider(1, 77));
    }

    private void insertReadyOrder(long id, String deliveryType) {
        jdbc.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address," +
                        "create_time,ready_time,delivery_type) VALUES(?,?,1,1,'test',2,'[]','{}'," +
                        "'2026-01-01 00:00:00','2026-01-01 00:10:00',?)",
                id, "NO" + id, deliveryType);
    }
}
