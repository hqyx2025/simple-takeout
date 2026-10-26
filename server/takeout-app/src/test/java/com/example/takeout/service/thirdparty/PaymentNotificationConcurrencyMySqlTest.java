package com.example.takeout.service.thirdparty;

import com.example.takeout.config.PaymentProperties;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.PaymentTransactionDao;
import com.example.takeout.service.mq.DomainEventPublisher;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.CompletableFuture;
import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class PaymentNotificationConcurrencyMySqlTest {
    @Test
    void paymentLockingReadsObserveCommitsBeyondAnEarlierRepeatableReadSnapshot() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1")
                + ":" + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        String database = "takeout_payment_read_" + UUID.randomUUID().toString().replace("-", "");
        JdbcTemplate admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        admin.execute("CREATE DATABASE `" + database + "`");
        try {
            var source = new DriverManagerDataSource(base + database + options, username, password);
            new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
            JdbcTemplate jdbc = new JdbcTemplate(source);
            PaymentTransactionDao payments = new PaymentTransactionDao(jdbc);
            var transaction = new TransactionTemplate(new DataSourceTransactionManager(source));
            transaction.setIsolationLevelName("ISOLATION_REPEATABLE_READ");
            transaction.executeWithoutResult(status -> {
                assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM payment_transactions", Integer.class));
                CompletableFuture.runAsync(() -> payments.insertPending(7, 2, "ALIPAY", new BigDecimal("13.00"),
                        "ALI-current", "2026-10-14 10:00:00")).orTimeout(10, TimeUnit.SECONDS).join();

                assertEquals("ALI-current", payments.findActiveByOrder(7).orElseThrow().outTradeNo());
            });
            transaction.executeWithoutResult(status -> {
                assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM payment_transactions WHERE status='SUCCESS'",
                        Integer.class));
                CompletableFuture.runAsync(() -> jdbc.update("UPDATE payment_transactions SET status='SUCCESS', " +
                        "provider_transaction_id='provider-current', active_order_id=NULL WHERE order_id=7"))
                        .orTimeout(10, TimeUnit.SECONDS).join();

                assertEquals("provider-current", payments.findSuccessfulByOrder(7).orElseThrow().providerTransactionId());
            });
        } finally {
            admin.execute("DROP DATABASE `" + database + "`");
        }
    }

    @Test
    void simultaneousSuccessNotificationsNeverRefundTheSamePaidOrder() throws Exception {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1")
                + ":" + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        String database = "takeout_payment_" + UUID.randomUUID().toString().replace("-", "");
        JdbcTemplate admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        admin.execute("CREATE DATABASE `" + database + "`");
        try {
            var source = new DriverManagerDataSource(base + database + options, username, password);
            new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
            JdbcTemplate jdbc = new JdbcTemplate(source);
            jdbc.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address," +
                    "pay_amount,create_time) VALUES(7,'NO7',2,3,'store',0,'[]','{}',13,NOW())");
            jdbc.update("INSERT INTO payment_transactions(order_id,user_id,channel,amount,out_trade_no,status," +
                    "active_order_id,create_time) VALUES(7,2,'ALIPAY',13,'ALI123','PENDING',7,NOW())");
            CountDownLatch snapshotsRead = new CountDownLatch(2);
            PaymentTransactionDao payments = spy(new PaymentTransactionDao(jdbc));
            doAnswer(invocation -> {
                Object row = invocation.callRealMethod();
                snapshotsRead.countDown();
                assertTrue(snapshotsRead.await(10, TimeUnit.SECONDS));
                return row;
            }).when(payments).findByOutTradeNo("ALI123");
            PaymentProperties properties = new PaymentProperties();
            properties.setRealEnabled(true);
            properties.setSandbox(false);
            properties.getAlipay().setGatewayUrl("https://openapi.alipay.com/gateway.do");
            properties.getAlipay().setAppPrivateKey("test-private");
            properties.getAlipay().setPublicKey("test-public");
            properties.getAlipay().setNotifyUrl("https://callback.example.test/api/payment/alipay/notify");
            PaymentGateway gateway = mock(PaymentGateway.class);
            when(gateway.channel()).thenReturn("ALIPAY");
            when(gateway.verifyNotification(anyString(), anyMap())).thenReturn(
                    new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1300, "CNY", true));
            ExternalPaymentService service = new ExternalPaymentService(properties, List.of(gateway), payments,
                    new OrderDao(jdbc), new PaymentRecordDao(jdbc), mock(DomainEventPublisher.class));
            var transaction = new TransactionTemplate(new DataSourceTransactionManager(source));
            transaction.setIsolationLevelName("ISOLATION_REPEATABLE_READ");
            service.configureTransactions(transaction);
            try (var executor = Executors.newFixedThreadPool(2)) {
                var first = executor.submit(() -> service.acceptNotification("ALIPAY", "raw", Map.of()));
                var second = executor.submit(() -> service.acceptNotification("ALIPAY", "raw", Map.of()));
                assertEquals(java.util.Set.of(ExternalPaymentService.NotificationResult.PAID,
                                ExternalPaymentService.NotificationResult.DUPLICATE),
                        java.util.Set.of(first.get(15, TimeUnit.SECONDS), second.get(15, TimeUnit.SECONDS)));
            }
            assertEquals(1, jdbc.queryForObject("SELECT status FROM orders WHERE id=7", Integer.class));
            assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM payment_records WHERE order_id=7", Integer.class));
            verify(gateway, never()).refund(anyString(), anyString(), any());
        } finally {
            admin.execute("DROP DATABASE `" + database + "`");
        }
    }
}
