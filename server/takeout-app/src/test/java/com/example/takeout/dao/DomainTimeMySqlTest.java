package com.example.takeout.dao;

import com.example.takeout.model.MarketingActivity;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class DomainTimeMySqlTest {

    private static final String NOW = "2026-10-14 12:00:00";
    private static final String BEFORE = "2026-10-14 11:00:00";
    private static final String AFTER = "2026-10-14 13:00:00";

    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private TransactionTemplate tx;
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
        database = "takeout_domain_time_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        var source = new DriverManagerDataSource(base + database + options, username, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        tx = new TransactionTemplate(new DataSourceTransactionManager(source));
    }

    @AfterEach
    void cleanUp() {
        if (database != null) {
            admin.execute("DROP DATABASE `" + database + "`");
        }
    }

    @Test
    void couponExpiryAndReleaseHandleLegacyWritesEmptyExpiryAndExactBoundary() {
        tx.executeWithoutResult(status -> {
            CouponDao dao = new CouponDao(jdbc);
            long future = dao.insert(7, 10, "future", 20, 5, AFTER, "test", NOW);
            assertEquals(AFTER, typedTime("coupons", "expire_time", future));
            assertEquals(NOW, typedTime("coupons", "create_time", future));
            long stale = dao.insert(7, 10, "stale", 20, 5, AFTER, "test", NOW);
            jdbc.update("UPDATE coupons SET expire_time = ? WHERE id = ?", BEFORE, stale);
            jdbc.update("INSERT INTO coupons(id,user_id,name,expire_time,create_time) " +
                    "VALUES(100,7,'legacy only',? ,?)", BEFORE, NOW);
            jdbc.update("INSERT INTO coupons(id,user_id,name,expire_time,create_time) " +
                    "VALUES(101,7,'invalid legacy','not-a-date',?), (102,7,'impossible date','2026-02-31 12:00:00',?)",
                    NOW, NOW);
            long unlimited = dao.insert(7, 10, "unlimited", 0, 5, "", "test", NOW);
            long boundary = dao.insert(7, 10, "boundary", 0, 5, NOW, "test", NOW);
            long usedExpired = dao.insert(7, 10, "used expired", 0, 5, BEFORE, "test", NOW);
            assertTrue(dao.markUsed(usedExpired));

            assertEquals(2, dao.expireOutdated(NOW));
            assertEquals(2, jdbc.queryForObject("SELECT status FROM coupons WHERE id = ?", Integer.class, stale));
            assertEquals(0, jdbc.queryForObject("SELECT status FROM coupons WHERE id = ?", Integer.class, future));
            assertNull(typedTime("coupons", "expire_time", unlimited));
            assertTrue(dao.markUsed(unlimited));
            assertTrue(dao.release(unlimited, NOW));
            assertFalse(dao.release(unlimited, NOW));
            assertTrue(dao.markUsed(boundary));
            assertTrue(dao.release(boundary, NOW));
            assertFalse(dao.release(usedExpired, NOW));
            assertTrue(dao.markUsed(future));
            jdbc.update("UPDATE coupons SET expire_time = ? WHERE id = ?", BEFORE, future);
            assertFalse(dao.release(future, NOW));

            new UserCouponDao(jdbc).insert(7, 10, "claimed", 20, 5, NOW, AFTER);
            long claim = jdbc.queryForObject("SELECT id FROM user_coupons WHERE user_id = 7", Long.class);
            assertEquals(NOW, typedTime("user_coupons", "claim_time", claim));
            assertEquals(AFTER, typedTime("user_coupons", "expire_time", claim));
        });
    }

    @Test
    void marketingWindowSupportsLegacyRowsEditsAndOldInstanceUpdates() {
        tx.executeWithoutResult(status -> {
            StoreDao dao = new StoreDao(jdbc);
            long active = dao.insertMarketingActivity(activity(0, BEFORE, AFTER, 1));
            assertEquals(BEFORE, typedTime("marketing_activities", "start_time", active));
            assertEquals(AFTER, typedTime("marketing_activities", "end_time", active));
            assertEquals(NOW, typedTime("marketing_activities", "create_time", active));
            jdbc.update("INSERT INTO marketing_activities(id,store_id,type,title,start_time,end_time,create_time) " +
                    "VALUES(100,10,'DISCOUNT','legacy',?,?,?)", BEFORE, NOW, NOW);
            long disabled = dao.insertMarketingActivity(activity(0, BEFORE, AFTER, 0));
            long future = dao.insertMarketingActivity(activity(0, AFTER, "2026-10-14 14:00:00", 1));

            assertEquals(Set.of(active, 100L), dao.listActiveMarketingActivities(10, NOW).stream()
                    .map(MarketingActivity::id).collect(java.util.stream.Collectors.toSet()));
            assertTrue(dao.listActiveMarketingActivities(11, NOW).isEmpty());
            dao.updateMarketingActivity(activity(active, AFTER, "2026-10-14 14:00:00", 1));
            assertEquals(AFTER, typedTime("marketing_activities", "start_time", active));
            assertEquals(List.of(100L), dao.listActiveMarketingActivities(10, NOW).stream()
                    .map(MarketingActivity::id).toList());

            // A still-running old application writes only VARCHAR; the old shadow must not activate this row.
            jdbc.update("UPDATE marketing_activities SET end_time = ? WHERE id = 100", BEFORE);
            jdbc.update("UPDATE marketing_activities SET start_time = ?, end_time = ? WHERE id = ?", BEFORE, AFTER, future);
            assertEquals(List.of(future), dao.listActiveMarketingActivities(10, NOW).stream()
                    .map(MarketingActivity::id).toList());
            assertEquals(0, dao.findMarketingActivityById(disabled).orElseThrow().status());
        });
    }

    @Test
    void seckillWindowsAndQuotaUseTypedTimesWithLegacyFallbackAfterEdits() {
        tx.executeWithoutResult(status -> {
            jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(10,'store',9,?)", NOW);
            jdbc.update("INSERT INTO goods(id,store_id,name,price,create_time) VALUES(100,10,'goods',20,?)", NOW);
            SeckillDao dao = new SeckillDao(jdbc);
            long id = dao.insert(100, 10, 10, 2, BEFORE, AFTER, 1);
            assertEquals(BEFORE, typedTime("seckills", "start_time", id));
            assertEquals(AFTER, typedTime("seckills", "end_time", id));
            assertEquals(dao.findById(id).orElseThrow().createTime(), typedTime("seckills", "create_time", id));
            assertEquals(id, dao.findActiveByGoods(100, NOW).orElseThrow().id());
            assertEquals(3600, dao.listActiveViews(10, NOW).get(0).remainSeconds());
            assertTrue(dao.deductQuota(id, 2, NOW));
            assertFalse(dao.deductQuota(id, 1, NOW));
            assertTrue(dao.findActiveByGoods(100, NOW).isEmpty());
            dao.restoreQuota(id, 2);

            dao.update(id, 10, 9, 2, AFTER, "2026-10-14 14:00:00", 1);
            assertEquals(AFTER, typedTime("seckills", "start_time", id));
            assertFalse(dao.deductQuota(id, 1, NOW));
            // Legacy-only writes can change both bounds while an outdated typed shadow remains.
            jdbc.update("UPDATE seckills SET start_time = ?, end_time = ? WHERE id = ?", BEFORE, NOW, id);
            assertEquals(id, dao.findActiveByGoods(100, NOW).orElseThrow().id());
            assertTrue(dao.deductQuota(id, 1, NOW));
            assertEquals(0, dao.listActiveViews(10, NOW).get(0).remainSeconds());
            assertFalse(dao.deductQuota(id, 1, AFTER));
            dao.update(id, 9, 3, BEFORE, AFTER, 1);
            assertEquals(BEFORE, typedTime("seckills", "start_time", id));
            assertEquals(AFTER, typedTime("seckills", "end_time", id));
            assertTrue(dao.joinOnce(7, id, 1, NOW));
            assertFalse(dao.joinOnce(7, id, 2, NOW));
            long participation = jdbc.queryForObject("SELECT id FROM seckill_orders WHERE user_id = 7", Long.class);
            assertEquals(NOW, typedTime("seckill_orders", "create_time", participation));

            jdbc.update("INSERT INTO seckills(id,goods_id,store_id,price,quota,start_time,end_time,create_time) " +
                    "VALUES(100,101,10,10,1,?,?,?)", BEFORE, AFTER, NOW);
            assertEquals(100, dao.findActiveByGoods(101, NOW).orElseThrow().id());
            assertTrue(dao.deductQuota(100, 1, NOW));
        });
    }

    @Test
    void outboxCleanupDeletesOnlySentEventsStrictlyBeforeCutoffAcrossLegacyWrites() {
        tx.executeWithoutResult(status -> {
            OutboxEventDao dao = new OutboxEventDao(jdbc, tx);
            long oldSent = dao.insert("ORDER_CREATED", 1, "{}", BEFORE);
            assertEquals(BEFORE, typedTime("outbox_events", "create_time", oldSent));
            dao.markSent(oldSent);
            long pending = dao.insert("ORDER_CREATED", 2, "{}", BEFORE);
            long atCutoff = dao.insert("ORDER_CREATED", 3, "{}", NOW);
            dao.markSent(atCutoff);
            long stale = dao.insert("ORDER_CREATED", 4, "{}", AFTER);
            dao.markSent(stale);
            jdbc.update("UPDATE outbox_events SET create_time = ? WHERE id = ?", BEFORE, stale);
            jdbc.update("INSERT INTO outbox_events(id,event_type,status,create_time) VALUES(100,'legacy',1,?)", BEFORE);
            jdbc.update("INSERT INTO outbox_events(id,event_type,status,create_time) VALUES(101,'blank',1,'')");
            jdbc.update("INSERT INTO outbox_events(id,event_type,status,create_time) " +
                    "VALUES(102,'invalid legacy',1,'not-a-date'), (103,'impossible date',1,'2026-02-31 12:00:00')");

            assertEquals(3, dao.deleteSentBefore(NOW));
            assertTrue(dao.findById(oldSent).isEmpty());
            assertTrue(dao.findById(stale).isEmpty());
            assertTrue(dao.findById(100).isEmpty());
            assertEquals(0, dao.findById(pending).orElseThrow().status());
            assertEquals(NOW, dao.findById(atCutoff).orElseThrow().createTime());
            assertTrue(dao.findById(101).isPresent());
            assertTrue(dao.findById(102).isPresent());
            assertTrue(dao.findById(103).isPresent());
            assertEquals(0, dao.deleteSentBefore(NOW));
        });
    }

    private MarketingActivity activity(long id, String start, String end, int status) {
        return new MarketingActivity(id, 10, "DISCOUNT", "activity", 0.8, 0, 0, 0, start, end, status, NOW);
    }

    private String typedTime(String table, String column, long id) {
        return jdbc.queryForObject("SELECT DATE_FORMAT(" + column + "_dt, '%Y-%m-%d %H:%i:%s') FROM " + table + " WHERE id = ?",
                String.class, id);
    }
}
