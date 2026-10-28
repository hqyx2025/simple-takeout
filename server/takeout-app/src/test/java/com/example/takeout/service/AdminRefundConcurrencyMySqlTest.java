package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.config.AfterSalesSchemaMigration;
import com.example.takeout.dao.*;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.example.takeout.service.thirdparty.ExternalPaymentService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;
import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

/** Real MySQL verifies order-first locking, atomic financial effects, and fresh/legacy schema upgrade. */
@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST", matches="1")
class AdminRefundConcurrencyMySqlTest {
    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private String database;
    private com.zaxxer.hikari.HikariDataSource source;
    private ExternalPaymentService payments;

    @BeforeEach
    void database() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1") + ":" +
                System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        database = "takeout_refund_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE " + database);
        source = new com.zaxxer.hikari.HikariDataSource();
        source.setJdbcUrl(base + database + options);source.setUsername(username);source.setPassword(password);
        source.setMaximumPoolSize(2);source.setMinimumIdle(0);source.setConnectionTimeout(10000);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        new AfterSalesSchemaMigration(jdbc).run(null);
        jdbc.update("INSERT INTO users(id,username,phone,password,balance,create_time) VALUES " +
                "(2,'customer','13800000002','test',0,NOW()),(4,'merchant','13800000004','test',2,NOW())");
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(3,'store',4,NOW())");
        jdbc.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address,delivery_fee," +
                "pay_amount,escrow_status,reviewed,create_time,complete_time) VALUES(7,'NO7',2,3,'store',4,'[]','{}',3,13,1,1,NOW(),NOW())");
        payments = mock(ExternalPaymentService.class);
        when(payments.refundOriginalPayment(any(), any(), anyLong(), anyBoolean())).thenReturn("BALANCE");
    }

    @AfterEach
    void cleanup() { if (source != null) source.close(); if (database != null) admin.execute("DROP DATABASE " + database); }

    private AfterSalesService service(OrderDao orders) {
        var target = new AfterSalesService(orders, new StoreDao(jdbc), new RefundDao(jdbc), new AfterSalesDao(jdbc),
                payments, new PaymentRecordDao(jdbc), mock(DomainEventPublisher.class), new ObjectMapper());
        var proxy = new ProxyFactory(target);
        proxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(source), new AnnotationTransactionAttributeSource()));
        return (AfterSalesService) proxy.getProxy();
    }

    @Test
    void settledPartialThenFullRefundRecordsDebtWithoutNegativeWalletAndKeepsRiderIncome() {
        AfterSalesService service = service(new OrderDao(jdbc));
        RefundRecord first = service.apply(2, 7, "OTHER", "餐损", "first", new BigDecimal("5.00"), List.of());
        service.approve(first.id());
        assertEquals(4, value("SELECT status FROM orders WHERE id=7"));
        assertEquals(1, value("SELECT escrow_status FROM orders WHERE id=7"));
        assertEquals(0, value("SELECT balance FROM users WHERE id=4"));
        assertEquals(5, value("SELECT balance FROM users WHERE id=2"));
        assertEquals(3, value("SELECT SUM(debt_amount) FROM after_sales_ledger"));
        RefundRecord second = service.apply(2, 7, "OTHER", "剩余退款", "second", null, List.of());
        service.approve(second.id());
        assertEquals(6, value("SELECT status FROM orders WHERE id=7"));
        assertEquals(2, value("SELECT escrow_status FROM orders WHERE id=7"));
        assertEquals(13, value("SELECT balance FROM users WHERE id=2"));
        assertEquals(10, value("SELECT SUM(merchant_amount) FROM refund_records"));
        assertEquals(3, value("SELECT SUM(platform_amount) FROM refund_records"));
        assertEquals(8, value("SELECT SUM(debt_amount) FROM after_sales_ledger"));
        assertEquals(13, value("SELECT SUM(amount) FROM payment_records WHERE type='REFUND'"));
        assertEquals(2, value("SELECT COUNT(*) FROM after_sales_ledger"));
        assertThrows(BizException.class, () -> service.approve(second.id()));
        assertEquals(13, value("SELECT balance FROM users WHERE id=2"));
        var order = new OrderDao(jdbc).findById(7).orElseThrow();
        service.payMerchantSettlement(order, new BigDecimal("10.00"));
        assertEquals(0, value("SELECT SUM(debt_amount) FROM after_sales_ledger"));
        assertEquals(8, value("SELECT SUM(amount) FROM after_sales_debt_payments"));
        assertEquals(2, value("SELECT balance FROM users WHERE id=4"));
    }

    @Test
    void failedProviderRefundRollsBackWalletDebtAndApplicationDecision() {
        AfterSalesService service = service(new OrderDao(jdbc));
        RefundRecord refund = service.apply(2, 7, "OTHER", "餐损", "first", new BigDecimal("5.00"), List.of());
        doThrow(new IllegalStateException("provider pending")).when(payments).refundOriginalPayment(any(), any(), anyLong(), anyBoolean());
        assertThrows(IllegalStateException.class, () -> service.approve(refund.id()));
        assertEquals(2, value("SELECT balance FROM users WHERE id=4"));
        assertEquals(0, value("SELECT balance FROM users WHERE id=2"));
        assertEquals(0, value("SELECT COUNT(*) FROM after_sales_ledger"));
        assertEquals("PENDING", jdbc.queryForObject("SELECT status FROM refund_records WHERE id=?", String.class, refund.id()));
    }

    @Test
    void approvalAndRejectionSerializeOnOrderBeforeRefund() throws Exception { decisions(true); }
    @Test
    void rejectionAndApprovalSerializeOnOrderBeforeRefund() throws Exception { decisions(false); }

    private void decisions(boolean approveFirst) throws Exception {
        CountDownLatch firstLocked = new CountDownLatch(1), secondAttempted = new CountDownLatch(1), release = new CountDownLatch(1);
        AtomicInteger attempts = new AtomicInteger();
        OrderDao orders = spy(new OrderDao(jdbc));
        var service = service(orders);
        RefundRecord refund = service.apply(2, 7, "OTHER", "餐损", "first", null, List.of());
        doAnswer(invocation -> {
            if (attempts.incrementAndGet() == 1) {
                Object result = invocation.callRealMethod(); firstLocked.countDown();
                assertTrue(release.await(10, TimeUnit.SECONDS)); return result;
            }
            secondAttempted.countDown(); return invocation.callRealMethod();
        }).when(orders).findByIdForUpdate(7);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> decide(service, refund.id(), approveFirst));
            assertTrue(firstLocked.await(10, TimeUnit.SECONDS));
            var second = executor.submit(() -> decide(service, refund.id(), !approveFirst));
            try {
                assertTrue(secondAttempted.await(10, TimeUnit.SECONDS));
                assertFalse(second.isDone());
            } finally { release.countDown(); }
            assertEquals(approveFirst ? "REFUNDED" : "REJECTED", first.get(15, TimeUnit.SECONDS).status());
            ExecutionException loser = assertThrows(ExecutionException.class, () -> second.get(15, TimeUnit.SECONDS));
            assertInstanceOf(BizException.class, loser.getCause());
            assertEquals("该退款申请已处理", loser.getCause().getMessage());
        } finally { release.countDown(); }
        assertEquals(approveFirst ? 13 : 0, value("SELECT balance FROM users WHERE id=2"));
        assertEquals(approveFirst ? 2 : 1, value("SELECT escrow_status FROM orders WHERE id=7"));
    }

    @Test
    void independentMigrationUpgradesOldRefundTableAndReplaysSafely() {
        jdbc.execute("DROP TABLE refund_records");
        jdbc.execute("CREATE TABLE refund_records(id BIGINT AUTO_INCREMENT PRIMARY KEY,order_id BIGINT,user_id BIGINT," +
                "merchant_id BIGINT,reason VARCHAR(255),amount DECIMAL(10,2),status VARCHAR(20),apply_time VARCHAR(32)," +
                "process_time VARCHAR(32),reject_reason VARCHAR(255))");
        jdbc.update("INSERT INTO refund_records(order_id,user_id,merchant_id,amount,status,apply_time,process_time) " +
                "VALUES(7,2,4,13,'REFUNDED',NOW(),NOW())");
        var migration = new AfterSalesSchemaMigration(jdbc);
        migration.run(null); migration.run(null);
        RefundRecord old = new RefundDao(jdbc).listByOrder(7).getFirst();
        assertEquals(new BigDecimal("10.00"), old.merchantAmount());
        assertEquals(new BigDecimal("3.00"), old.platformAmount());
        assertNotNull(old.refundTime());
    }

    private int value(String sql) { return jdbc.queryForObject(sql, Integer.class); }
    private RefundRecord decide(AfterSalesService service, long id, boolean approve) {
        return approve ? service.approve(id) : service.reject(id, "无法核实");
    }
}
