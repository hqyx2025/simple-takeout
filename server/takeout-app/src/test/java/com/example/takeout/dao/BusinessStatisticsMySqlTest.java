package com.example.takeout.dao;

import com.example.takeout.config.AfterSalesSchemaMigration;
import com.example.takeout.model.Goods;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;
import java.util.stream.IntStream;

import static org.junit.jupiter.api.Assertions.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class BusinessStatisticsMySqlTest {
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private com.zaxxer.hikari.HikariDataSource pool;
    private String database;

    @BeforeEach
    void setUp() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1") + ":" +
                System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        database = "takeout_statistics_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        var source = new com.zaxxer.hikari.HikariDataSource();pool=source;
        source.setJdbcUrl(base + database + options);source.setUsername(username);source.setPassword(password);
        source.setMaximumPoolSize(2);source.setMinimumIdle(0);source.setConnectionTimeout(10000);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        new AfterSalesSchemaMigration(jdbc).run(null);
        jdbc.update("INSERT INTO stores(id,name,owner_id,monthly_sales,create_time) VALUES(1,'real',10,9999,?), (2,'other',11,8888,?)", stamp(LocalDateTime.now()), stamp(LocalDateTime.now()));
        jdbc.update("INSERT INTO goods(id,store_id,name,sales,create_time) VALUES(1,1,'real',9999,?), (2,2,'other',0,?), (3,1,'seed only',8888,?)", stamp(LocalDateTime.now()), stamp(LocalDateTime.now()), stamp(LocalDateTime.now()));
    }

    @AfterEach
    void cleanUp() {
        if (pool != null) pool.close();
        if (database != null) admin.execute("DROP DATABASE `" + database + "`");
    }

    @Test
    void browsingAndAdminRanksUsePaidQuantitiesAndOrderCountsWithoutSeedSales() {
        LocalDateTime now = LocalDateTime.now().minusMinutes(1);
        order(1, 1, 0, 0, "", stamp(now), 100, 10, 100);
        order(2, 1, 1, 0, stamp(now), stamp(now), 100, 10, 2);
        order(3, 1, 4, 1, stamp(now), stamp(now), 100, 10, 3);
        order(4, 1, 5, 2, stamp(now), stamp(now), 100, 10, 50);
        order(5, 1, 6, 2, stamp(now), stamp(now), 100, 10, 60);
        order(6, 1, 6, 1, stamp(now), stamp(now), 100, 10, 4);
        order(7, 1, 4, 1, stamp(now), stamp(now), 100, 10, 5);
        refund(7, 10, 10, 1, "REFUNDED", stamp(now));
        order(8, 1, 4, 1, stamp(now.minusDays(31)), stamp(now), 100, 10, 70);
        order(9, 1, 1, 0, stamp(now.plusDays(1)), stamp(now), 100, 10, 80);
        order(10, 1, 1, 0, stamp(now), stamp(now.minusDays(40)), 100, 10, 6);
        order(11, 2, 1, 0, stamp(now), stamp(now), 100, 10, 7);
        GoodsDao goods = new GoodsDao(jdbc, new GoodsSpecDao(jdbc));
        assertEquals(List.of(1L, 3L), goods.listByStore(1).stream().map(Goods::id).toList());
        assertEquals(20, goods.findById(1).orElseThrow().sales());
        assertEquals(0, goods.findById(3).orElseThrow().sales());
        assertEquals(20, goods.listByStoreAll(1).getFirst().sales());
        assertEquals(20, goods.listForAdmin(null, null).stream().filter(g -> g.id() == 1).findFirst().orElseThrow().sales());
        assertEquals(1, goods.listTopGoods(10).getFirst().goods().id());
        StoreDao stores = new StoreDao(jdbc);
        assertEquals(5, stores.findById(1).orElseThrow().monthlySales());
        assertEquals(1, stores.listAll().getFirst().id());
        AdminStatsDao stats = new AdminStatsDao(jdbc);
        assertEquals(20, stats.overview(10).hotGoods().getFirst().sales());
        var top = stats.topStores(10).getFirst();
        assertEquals(1, top.storeId());
        assertEquals(5, top.orderCount());
        assertEquals(490, top.gmv(), 0.001);
        // 资料旧快照不得覆盖并发更新的评分、平台控制字段和旧统计列。
        var stale = stores.findById(1).orElseThrow();
        jdbc.update("UPDATE stores SET rating=4.9,monthly_sales=123,status=0,recommended=1 WHERE id=1");
        stores.update(stale);
        assertEquals(4.9, jdbc.queryForObject("SELECT rating FROM stores WHERE id=1", Double.class), 0.001);
        assertEquals(123, jdbc.queryForObject("SELECT monthly_sales FROM stores WHERE id=1", Integer.class));
        assertEquals(0, stores.findById(1).orElseThrow().status());
        assertEquals(1, stores.findById(1).orElseThrow().recommended());
    }

    @Test
    void thirtyDayWindowUsesPaymentBoundaryAndFallsBackWhenDatetimeShadowIsStale() {
        String end = "2026-10-28 12:00:00";
        order(1, 1, 1, 0, "2026-09-28 12:00:00", "2026-08-01 00:00:00", 10, 0, 2);
        order(2, 1, 1, 0, "2026-09-28 11:59:59", end, 10, 0, 100);
        order(3, 1, 1, 0, end, end, 10, 0, 3);
        order(4, 1, 1, 0, "2026-10-28 12:00:01", end, 10, 0, 100);
        order(5, 1, 1, 0, "not-a-date", end, 10, 0, 100);
        jdbc.update("UPDATE orders SET pay_time_dt='2026-01-01 00:00:00' WHERE id=1");
        Long quantity = jdbc.queryForObject("SELECT COALESCE(sold.sales,0) FROM goods g " + GoodsDao.MONTHLY_SALES_JOIN +
                " WHERE g.id=1", Long.class, end, end);
        assertEquals(5, quantity);
    }

    @Test
    void settlementAndRefundEventsUseTheirOwnDatesWithoutDoubleSubtractingPreSettlementRefunds() {
        String yesterday = "2026-10-27 12:00:00";
        String today = "2026-10-28 12:00:00";
        order(1, 1, 6, 1, yesterday, "2026-10-01 12:00:00", 100, 10, 1);
        settlement(1, 90, yesterday);
        refund(1, 20, 20, 1, "REFUNDED", today);
        order(2, 1, 4, 1, yesterday, yesterday, 100, 10, 1);
        refund(2, 30, 30, 0, "REFUNDED", yesterday);
        settlement(2, 60, today);
        order(3, 1, 4, 1, today, today, 3, 5, 1); // 折扣后支付小于配送费，商户净额为0。
        order(4, 1, 4, 1, today, today, 50, 5, 1); // 历史订单无结算事实。
        refund(4, 5, 5, 0, "REFUNDED", yesterday);
        order(5, 1, 6, 2, yesterday, yesterday, 45, 5, 1);
        settlement(5, 40, yesterday);
        refund(5, 45, 40, 1, "REFUNDED", today);
        order(6, 1, 4, 0, today, today, 80, 5, 1); // 未确认托管不能算收入。
        order(7, 1, 6, 1, yesterday, yesterday, 20, 2, 1);
        refund(7, 10, 10, 1, "PENDING", today); // 申请中不能扣款。
        var dao = new OrderDao(jdbc);
        var previous = aggregate(dao, LocalDate.of(2026, 10, 27));
        var current = aggregate(dao, LocalDate.of(2026, 10, 28));
        assertEquals(148, previous.todayIncome(), 0.001); // 90+40+18，不被次日退款回改。
        assertEquals(40, current.todayIncome(), 0.001); // 60+40-20-40。
        assertEquals(188, current.totalIncome(), 0.001);
        assertEquals(previous.todayIncome(), current.dayIncome().get(5), 0.001);
        assertEquals(current.todayIncome(), current.dayIncome().get(6), 0.001);
        assertEquals(3, current.todayCompleted()); // 实际今日结算2、历史完成3/4。
        jdbc.update("UPDATE refund_records SET refund_time='2026-10-29 12:00:00' WHERE settled_before=1 AND status='REFUNDED'");
        assertEquals(-60, aggregate(dao, LocalDate.of(2026, 10, 29)).todayIncome(), 0.001);
    }

    private OrderDao.MerchantStatsAggregate aggregate(OrderDao dao, LocalDate day) {
        List<String> days = IntStream.rangeClosed(0, 6).mapToObj(i -> stamp(day.minusDays(6 - i).atStartOfDay())).toList();
        return dao.aggregateMerchantStats(1, stamp(day.atStartOfDay()), stamp(day.plusDays(1).atStartOfDay()),
                days.getFirst(), stamp(day.withDayOfMonth(1).atStartOfDay()), days);
    }

    private void order(long id, long store, int status, int escrow, String paidAt, String completeAt, double pay, double fee, int quantity) {
        jdbc.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address,pay_amount,delivery_fee,escrow_status,create_time,pay_time,complete_time) " +
                "VALUES(?,?,1,?,'store',?,'[]','{}',?,?,?,?,?,?)", id, "STATS" + id, store, status, pay, fee, escrow, completeAt, paidAt, completeAt);
        jdbc.update("INSERT INTO order_items(order_id,line_no,goods_id,goods_name,unit_price,quantity) VALUES(?,1,?,'goods',10,?)", id, store, quantity);
    }

    private void settlement(long order, double net, String at) {
        jdbc.update("INSERT INTO order_settlements(order_id,merchant_id,net_amount,debt_repaid,wallet_credited,settled_at) VALUES(?,10,?,0,?,?)", order, net, net, at);
    }

    private void refund(long order, double amount, double merchant, int settledBefore, String status, String at) {
        jdbc.update("INSERT INTO refund_records(order_id,user_id,merchant_id,amount,merchant_amount,platform_amount,settled_before,status,apply_time,process_time,refund_time) " +
                "VALUES(?,1,10,?,?,?,?,?,?,?,?)", order, amount, merchant, amount - merchant, settledBefore, status, at, at, at);
    }

    private String stamp(LocalDateTime value) {
        return value.format(FMT);
    }
}
