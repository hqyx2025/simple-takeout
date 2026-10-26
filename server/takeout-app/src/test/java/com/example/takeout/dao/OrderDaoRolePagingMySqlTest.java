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
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Opt-in MySQL checks for role-scoped pagination joins, filters and ordering. */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class OrderDaoRolePagingMySqlTest {

    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private String database;
    private OrderDao dao;

    @BeforeEach
    void setUp() {
        String host = System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1");
        String port = System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310");
        String base = "jdbc:mysql://" + host + ":" + port + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        database = "takeout_order_page_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        var source = new DriverManagerDataSource(base + database + options, username, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        dao = new OrderDao(jdbc);

        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(10,'merchant store',9,'2026-01-01')");
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(11,'merchant store two',9,'2026-01-01')");
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(12,'other store',10,'2026-01-01')");
        jdbc.update("INSERT INTO employees(store_id,user_id,role_name,status,create_time) " +
                "VALUES(12,21,'店员',1,'2026-01-01')");
        insertOrder(1, 7, 10, 1, 0, "", "");
        insertOrder(2, 7, 11, 0, 0, "", "");
        insertOrder(3, 7, 12, 4, 0, "", "2026-10-14 12:00:00");
        insertOrder(4, 7, 10, 4, 0, "", "2026-10-14 13:00:00");
        insertOrder(5, 20, 10, 2, 77, "2026-10-14 10:00:00", "");
        insertOrder(6, 20, 10, 3, 77, "2026-10-14 09:00:00", "");
        insertOrder(7, 20, 10, 4, 77, "2026-10-14 08:00:00", "2026-10-14 11:00:00");
    }

    @AfterEach
    void cleanUp() {
        if (database != null) {
            admin.execute("DROP DATABASE `" + database + "`");
        }
    }

    @Test
    void userStatusPageAndMerchantOwnerPageReturnOnlyMatchingRows() {
        assertEquals(2, dao.countByUser(7, 4));
        assertEquals(3, dao.listByUser(7, 4, 1, 1).get(0).id());

        assertEquals(5, dao.countByMerchant(9, null));
        assertEquals(2, dao.countByMerchant(9, 4));
        assertEquals(7, dao.listByMerchant(9, 4, 1, 0).get(0).order().id());
        assertEquals(1, dao.countByMerchant(21, null));
        assertEquals(3, dao.listByMerchant(21, null, 10, 0).get(0).order().id());
    }

    @Test
    void riderPagesKeepWorkInProgressAheadOfCompletedOrders() {
        assertEquals(3, dao.countByRider(77));
        var firstPage = dao.listByRider(77, 2, 0);
        assertEquals(6, firstPage.get(0).id());
        assertEquals(5, firstPage.get(1).id());
        assertEquals(7, dao.listByRider(77, 1, 2).get(0).id());
    }

    @Test
    void datetimeQueriesReadLegacyOnlyRowsAndFollowOldInstanceEdits() {
        jdbc.update("UPDATE orders SET status = 1 WHERE id = 2");
        insertOrder(8, 7, 10, 0, 0, "", "");
        jdbc.update("UPDATE orders SET create_time = ? WHERE id = ?", "2026-10-14 09:00:00", 8);
        insertOrder(9, 7, 10, 0, 0, "", "");
        jdbc.update("UPDATE orders SET create_time = ?, create_time_dt = ? WHERE id = ?",
                "2099-12-31 00:00:00", "2026-10-14 09:30:00", 9);

        var expired = dao.listExpiredPending("2026-10-14 10:00:00");

        org.junit.jupiter.api.Assertions.assertEquals(java.util.Set.of(8L),
                expired.stream().map(order -> order.id()).collect(java.util.stream.Collectors.toSet()));
        assertEquals("2099-12-31 00:00:00", dao.findById(9).orElseThrow().createTime());
        jdbc.update("UPDATE orders SET create_time = ? WHERE id = ?", "2026-10-14 08:00:00", 9);
        assertEquals(java.util.Set.of(8L, 9L), dao.listExpiredPending("2026-10-14 10:00:00").stream()
                .map(order -> order.id()).collect(java.util.stream.Collectors.toSet()));
        assertTrue(dao.markPaid(8, "2026-10-14 10:05:00"));
        var written = jdbc.queryForMap("SELECT pay_time, DATE_FORMAT(pay_time_dt, '%Y-%m-%d %H:%i:%s') AS pay_time_dt " +
                "FROM orders WHERE id = 8");
        assertEquals("2026-10-14 10:05:00", written.get("pay_time").toString());
        assertEquals("2026-10-14 10:05:00", written.get("pay_time_dt").toString());
    }

    private void insertOrder(long id, long userId, long storeId, int status, long riderId,
                             String readyTime, String completeTime) {
        jdbc.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address,create_time," +
                        "rider_id,ready_time,complete_time) VALUES(?,?,?,?,?,?, '[]','{}','2026-10-14 09:00:00',?,?,?)",
                id, "PAGE-" + id, userId, storeId, "store", status, riderId, readyTime, completeTime);
    }
}
