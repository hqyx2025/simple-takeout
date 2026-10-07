package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.Order;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.core.io.ClassPathResource;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.dao.CannotAcquireLockException;
import org.springframework.dao.DataAccessResourceFailureException;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

/**
 * Opt-in real MySQL regression. Creates and drops only its own random database;
 * never writes to takeout. Set TAKEOUT_MYSQL_CONCURRENCY_TEST=1 and DB credentials.
 */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class OrderConcurrencyMySqlTest {
    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private String database;
    private OrderService service;
    private PaymentRecordDao paymentRecords;
    private OutboxEventDao outbox;
    private HotDataCacheService cache;

    @BeforeEach
    void setUp() {
        String host = System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1");
        String port = System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310");
        String base = "jdbc:mysql://" + host + ":" + port + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        database = "takeout_concurrency_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        var source = new DriverManagerDataSource(base + database + options, username, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        var transactions = new TransactionTemplate(new DataSourceTransactionManager(source));
        paymentRecords = spy(new PaymentRecordDao(jdbc));
        outbox = spy(new OutboxEventDao(jdbc, transactions));
        cache = mock(HotDataCacheService.class);
        var specs = new GoodsSpecDao(jdbc);
        var target = new OrderService(new OrderDao(jdbc), new StoreDao(jdbc), new GoodsDao(jdbc, specs),
                new AddressDao(jdbc), new CouponDao(jdbc), new ReviewDao(jdbc), new UserDao(jdbc),
                new RefundDao(jdbc), new ObjectMapper(), mock(CartItemMapper.class), new RiderDao(jdbc),
                specs, new SeckillDao(jdbc), cache,
                new DomainEventPublisher(outbox, mock(ObjectProvider.class), new ObjectMapper()),
                mock(ObjectProvider.class), paymentRecords);
        target.configureTransactions(transactions);
        var proxy = new ProxyFactory(target);
        proxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(source),
                new AnnotationTransactionAttributeSource()));
        service = (OrderService) proxy.getProxy();
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(10,'test',99,'2026-01-01 00:00:00')");
        for (int id = 1; id <= 8; id++) {
            jdbc.update("INSERT INTO users(id,username,phone,password,balance,create_time) VALUES(?,?,?,'test',1000,?)",
                    id, "user" + id, "1380000000" + id, "2026-01-01 00:00:00");
            jdbc.update("INSERT INTO addresses(id,user_id,name,phone,detail,create_time) VALUES(?,?,'test','test','test',?)",
                    id, id, "2026-01-01 00:00:00");
            jdbc.update("INSERT INTO coupons(id,user_id,name,amount,expire_time,create_time) VALUES(?,?,'test',1,'2099-01-01 00:00:00',?)",
                    id, id, "2026-01-01 00:00:00");
        }
        for (int id = 100; id <= 102; id++) {
            jdbc.update("INSERT INTO goods(id,store_id,name,price,stock,create_time) VALUES(?,10,?,10,1000,?)",
                    id, "goods" + id, "2026-01-01 00:00:00");
        }
        jdbc.update("INSERT INTO goods_specs(id,goods_id,name,price,stock,create_time) VALUES(300,102,'large',10,1000,?)",
                "2026-01-01 00:00:00");
        for (int id = 100; id <= 101; id++) {
            jdbc.update("INSERT INTO seckills(id,goods_id,store_id,price,quota,start_time,end_time,create_time) "
                            + "VALUES(?,?,10,5,1000,'2026-01-01','2099-01-01',?)", id, id, "2026-01-01 00:00:00");
        }
    }

    @AfterEach
    void cleanUp() {
        if (database != null) {
            admin.execute("DROP DATABASE `" + database + "`");
        }
    }

    @Test
    void parallelCreateAndCancelWithReverseItemOrderRestoresAllReservations() throws Exception {
        runTogether(8, index -> {
            long userId = index + 1;
            for (int iteration = 0; iteration < 12; iteration++) {
                List<Order.OrderItem> items = index % 2 == 0
                        ? List.of(item(100, 0), item(101, 0), item(102, 300))
                        : List.of(item(102, 300), item(101, 0), item(100, 0));
                Order.OrderView created = service.createOrder(userId, 10, items, userId, userId, "");
                assertEquals(0, created.status());
                assertEquals(5, service.cancelOrder(userId, created.id()).status());
            }
        });
        assertEquals(96, count("SELECT COUNT(*) FROM orders WHERE status=5"));
        assertEquals(3, count("SELECT COUNT(*) FROM goods WHERE stock=1000"));
        assertEquals(1000, count("SELECT stock FROM goods_specs WHERE id=300"));
        assertEquals(0, count("SELECT SUM(sold) FROM seckills"));
        assertEquals(0, count("SELECT COUNT(*) FROM seckill_orders"));
        assertEquals(0, count("SELECT COUNT(*) FROM coupons WHERE status<>0"));
        assertEquals(8, count("SELECT COUNT(*) FROM users WHERE balance=1000"));
        assertEquals(192, count("SELECT COUNT(*) FROM outbox_events"));
    }

    @Test
    void simultaneousPayAndCancelNeverDoubleRefundOrLoseStock() throws Exception {
        for (int iteration = 0; iteration < 12; iteration++) {
            long id = service.createOrder(1, 10, List.of(item(102, 300)), 1, 0, "").id();
            runTogether(3, index -> {
                try {
                    if (index == 0) service.payOrder(1, id, "BALANCE");
                    else service.cancelOrder(1, id);
                } catch (BizException expectedStateConflict) {
                    // Only the winner may change the state, balance and stock.
                }
            });
            if (service.orderDetail(id).status() != 5) service.cancelOrder(1, id);
            assertEquals(5, service.orderDetail(id).status());
            assertTrue(count("SELECT COUNT(*) FROM payment_records WHERE type='REFUND' AND order_id=" + id) <= 1);
            assertEquals(1000, count("SELECT balance FROM users WHERE id=1"));
            assertEquals(1000, count("SELECT stock FROM goods WHERE id=102"));
            assertEquals(1000, count("SELECT stock FROM goods_specs WHERE id=300"));
        }
    }

    private Order.OrderItem item(long goodsId, long specId) {
        return new Order.OrderItem(goodsId, "test", 0, 1, "", specId, "", 0);
    }

    @Test
    void limitedSkuStockCannotBeOversoldAndDuplicateCancellationDoesNotRestoreTwice() throws Exception {
        jdbc.update("UPDATE goods SET stock=2 WHERE id=102");
        jdbc.update("UPDATE goods_specs SET stock=2 WHERE id=300");
        runTogether(8, index -> {
            long userId = index + 1;
            try {
                service.createOrder(userId, 10, List.of(item(102, 300)), userId, 0, "");
            } catch (BizException insufficientStock) {
                assertTrue(insufficientStock.getMessage().contains("库存不足"));
            }
        });
        assertEquals(2, count("SELECT COUNT(*) FROM orders"));
        assertEquals(0, count("SELECT stock FROM goods WHERE id=102"));
        assertEquals(0, count("SELECT stock FROM goods_specs WHERE id=300"));
        List<Order> orders = new OrderDao(jdbc).listAll();
        runTogether(8, index -> {
            Order order = orders.get(index % 2);
            try {
                service.cancelOrder(order.userId(), order.id());
            } catch (BizException alreadyCancelled) {
                // Only one cancellation may restore each reservation.
            }
        });
        assertEquals(2, count("SELECT stock FROM goods WHERE id=102"));
        assertEquals(2, count("SELECT stock FROM goods_specs WHERE id=300"));
    }

    @Test
    void timeoutScanAndManualCancellationReleaseCouponAndStockOnce() throws Exception {
        for (int userId = 1; userId <= 8; userId++) {
            service.createOrder(userId, 10, List.of(item(102, 300)), userId, userId, "");
        }
        jdbc.update("UPDATE orders SET create_time='2026-01-01 00:00:00'");
        List<Order> orders = new OrderDao(jdbc).listAll();
        runTogether(3, index -> {
            if (index < 2) service.cancelExpiredPendingOrders();
            else for (Order order : orders) {
                try {
                    service.cancelOrder(order.userId(), order.id());
                } catch (BizException alreadyCancelled) {
                    // Conditional state transition chooses the winner.
                }
            }
        });
        assertEquals(8, count("SELECT COUNT(*) FROM orders WHERE status=5"));
        assertEquals(1000, count("SELECT stock FROM goods_specs WHERE id=300"));
        assertEquals(1000, count("SELECT stock FROM goods WHERE id=102"));
        assertEquals(0, count("SELECT COUNT(*) FROM coupons WHERE status<>0"));
    }

    @Test
    void paymentLedgerFailureRollsBackStateAndBalanceOnThreeArgumentPaymentEntry() {
        long id = service.createOrder(1, 10, List.of(item(102, 300)), 1, 0, "").id();
        doThrow(new DataAccessResourceFailureException("injected ledger failure"))
                .when(paymentRecords).insert(eq(id), anyLong(), anyDouble(), eq("PAY"), anyString(), anyString(), anyString());

        assertThrows(DataAccessResourceFailureException.class, () -> service.payOrder(1, id, "BALANCE"));

        assertEquals(0, service.orderDetail(id).status());
        assertEquals(1000, count("SELECT balance FROM users WHERE id=1"));
        assertEquals(0, count("SELECT COUNT(*) FROM payment_records"));
        assertEquals(0, count("SELECT COUNT(*) FROM outbox_events WHERE event_type='ORDER_PAID'"));
    }

    @Test
    void outboxDatabaseFailureRollsBackCancellationAndDoesNotInvalidateCache() {
        long id = service.createOrder(1, 10, List.of(item(100, 0)), 1, 1, "").id();
        clearInvocations(cache);
        doThrow(new CannotAcquireLockException("injected outbox deadlock"))
                .when(outbox).insert(eq(DomainEventPublisher.ORDER_CANCELLED), eq(id), anyString(), anyString());

        assertThrows(CannotAcquireLockException.class, () -> service.cancelOrder(1, id));

        assertEquals(0, service.orderDetail(id).status());
        assertEquals(999, count("SELECT stock FROM goods WHERE id=100"));
        assertEquals(1, count("SELECT sold FROM seckills WHERE id=100"));
        assertEquals(1, count("SELECT COUNT(*) FROM seckill_orders"));
        assertEquals(1, count("SELECT status FROM coupons WHERE id=1"));
        verify(cache, never()).evictByPattern(anyString());
    }

    private int count(String sql) {
        return jdbc.queryForObject(sql, Integer.class);
    }

    private void runTogether(int workers, Work work) throws Exception {
        var start = new CountDownLatch(1);
        try (var pool = Executors.newFixedThreadPool(workers)) {
            List<Future<?>> futures = new ArrayList<>();
            for (int i = 0; i < workers; i++) {
                int index = i;
                futures.add(pool.submit(() -> {
                    assertTrue(start.await(10, TimeUnit.SECONDS));
                    work.run(index);
                    return null;
                }));
            }
            start.countDown();
            try {
                for (Future<?> future : futures) future.get(45, TimeUnit.SECONDS);
            } finally {
                pool.shutdownNow();
            }
        }
    }

    private interface Work {
        void run(int index) throws Exception;
    }
}
