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
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time,latitude,longitude) VALUES(1,'near',1,NOW(),22.8,108.3),(2,'far',1,NOW(),23.8,108.3),(3,'unknown',1,NOW(),NULL,NULL)");
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

        assertEquals(1, dao.listRiderPool(22.8, 108.3, 25000, 30, 0L).size());
        assertEquals(1, dao.listRiderPool(22.8, 108.3, 25000, 30, 0L).getFirst().order().id());
        assertFalse(dao.tryAssignRider(2, 77));
        assertEquals(0, jdbc.queryForObject("SELECT rider_id FROM orders WHERE id=2", Integer.class));
        assertTrue(dao.tryAssignRider(1, 77));
    }

    @Test
    void filtersBeforePagingAndOrdersTiesById() {
        for (int id = 3; id <= 205; id++) insertReadyOrder(id, "DELIVERY");
        jdbc.update("UPDATE orders SET store_id=2 WHERE id BETWEEN 3 AND 102");
        jdbc.update("UPDATE orders SET store_id=3 WHERE id=103");
        jdbc.update("INSERT INTO order_fulfillment(order_id,mode) VALUES(104,'MERCHANT'),(105,'RIDER')");
        OrderDao dao = new OrderDao(jdbc);
        assertEquals(102, dao.countRiderPool(22.8, 108.3, 25000));
        var first = dao.listRiderPool(22.8, 108.3, 25000, 30, 0L);
        var second = dao.listRiderPool(22.8, 108.3, 25000, 30, 30L);
        assertEquals(1, first.getFirst().order().id());
        assertEquals(105, first.get(1).order().id());
        assertEquals(133, first.getLast().order().id());
        assertEquals(134, second.getFirst().order().id());
        assertTrue(first.stream().noneMatch(a -> second.stream().anyMatch(b -> a.order().id()==b.order().id())));
        assertEquals(12, dao.listRiderPool(22.8, 108.3, 25000, 30, 90L).size());
        assertTrue(dao.listRiderPool(22.8, 108.3, 25000, 30, 120L).isEmpty());
        assertEquals("2026-01-01 00:10:00", first.getFirst().readyTime());
        assertEquals(first.stream().map(row -> row.order().id()).toList(),
                dao.listRiderPoolAfter(22.8, 108.3, 25000, 30, 0L).stream().map(row -> row.order().id()).toList());
    }

    @Test
    void cursorDoesNotSkipUnreadOrdersWhenPreviousOrdersAreClaimed() {
        for (int id = 3; id <= 72; id++) insertReadyOrder(id, "DELIVERY");
        OrderDao dao = new OrderDao(jdbc);
        var first = dao.listRiderPoolAfter(22.8, 108.3, 25000, 10, 0);
        long cursor = first.getLast().order().id();
        assertEquals(11, cursor);
        jdbc.update("UPDATE orders SET rider_id=77 WHERE id IN (1,3,11)");
        // 更小 id 的订单刚出餐，排序应以出餐时间为主，不能只按订单 id 翻页。
        jdbc.update("UPDATE orders SET delivery_type='DELIVERY',ready_time='2026-01-01 00:20:00' WHERE id=2");
        insertReadyOrder(100, "DELIVERY");
        jdbc.update("UPDATE orders SET ready_time='2026-01-01 00:05:00' WHERE id=100");

        var next = dao.listRiderPoolAfter(22.8, 108.3, 25000, 10, cursor);
        assertEquals(java.util.stream.LongStream.rangeClosed(12, 21).boxed().toList(),
                next.stream().map(row -> row.order().id()).toList());
        assertEquals(14, dao.listRiderPool(22.8, 108.3, 25000, 10, 10).getFirst().order().id(),
                "旧 OFFSET 分页在池子缩减后确实会跳过未读订单");
        var tail = dao.listRiderPoolAfter(22.8, 108.3, 25000, 100, cursor);
        assertEquals(2, tail.getLast().order().id());
        assertEquals(100, dao.listRiderPoolAfter(22.8, 108.3, 25000, 1, 0).getFirst().order().id());
    }

    @Test
    void cursorOrdersInvalidLegacyTimesConsistently() {
        for (int id = 3; id <= 5; id++) insertReadyOrder(id, "DELIVERY");
        jdbc.update("UPDATE orders SET ready_time='legacy-invalid' WHERE id IN (1,3)");
        jdbc.update("UPDATE orders SET ready_time='' WHERE id=4");
        OrderDao dao = new OrderDao(jdbc);
        assertEquals(1, dao.listRiderPoolAfter(22.8, 108.3, 25000, 1, 0).getFirst().order().id());
        assertEquals(3, dao.listRiderPoolAfter(22.8, 108.3, 25000, 1, 1).getFirst().order().id());
        assertEquals(5, dao.listRiderPoolAfter(22.8, 108.3, 25000, 1, 3).getFirst().order().id());
        assertTrue(dao.listRiderPoolAfter(22.8, 108.3, 25000, 1, 5).isEmpty());
    }

    private void insertReadyOrder(long id, String deliveryType) {
        jdbc.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address," +
                        "create_time,ready_time,delivery_type) VALUES(?,?,1,1,'test',2,'[]','{}'," +
                        "'2026-01-01 00:00:00','2026-01-01 00:10:00',?)",
                id, "NO" + id, deliveryType);
    }
}
