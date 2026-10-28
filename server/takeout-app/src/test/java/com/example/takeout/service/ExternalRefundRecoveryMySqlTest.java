package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.config.PaymentProperties;
import com.example.takeout.config.AfterSalesSchemaMigration;
import com.example.takeout.dao.*;
import com.example.takeout.job.ExternalRefundRecoveryJob;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.Order;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.example.takeout.service.thirdparty.ExternalPaymentService;
import com.example.takeout.service.thirdparty.PaymentGateway;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;
import org.springframework.transaction.support.TransactionTemplate;
import java.math.BigDecimal;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

/** At most two pooled connections: one business transaction plus one independent intent transaction. */
@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST", matches="1")
class ExternalRefundRecoveryMySqlTest {
    private HikariDataSource source;
    private JdbcTemplate admin, db;
    private String database;
    private DataSourceTransactionManager manager;
    private ExternalRefundAttemptService attempts;
    private ExternalPaymentService payments;
    private AfterSalesService sales;
    private OrderService orders;
    private AdminService admins;
    private ExternalRefundRecoveryJob recovery;
    private DomainEventPublisher events;
    private PaymentRecordDao records;
    private PaymentGateway gateway;
    private final RiderDao riders = mock(RiderDao.class);
    private final Map<String, BigDecimal> remoteRefunds = new HashMap<>();
    private final List<String> channelCalls = new ArrayList<>();
    private final AtomicBoolean loseChannelResponse = new AtomicBoolean();

    @BeforeEach
    void setUp() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1") + ":" +
                System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root"), password = System.getenv("TAKEOUT_DB_PASSWORD");
        database = "refund_recovery_" + UUID.randomUUID().toString().replace("-", "");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        admin.execute("CREATE DATABASE " + database);
        source = new HikariDataSource(); source.setJdbcUrl(base + database + options);
        source.setUsername(username); source.setPassword(password); source.setMaximumPoolSize(2);
        source.setMinimumIdle(0); source.setConnectionTimeout(5000);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        db = new JdbcTemplate(source); new AfterSalesSchemaMigration(db).run(null);
        manager = new DataSourceTransactionManager(source);
        db.update("INSERT INTO users(id,username,phone,password,balance,create_time) VALUES " +
                "(2,'customer','13800000002','test',0,NOW()),(4,'merchant','13800000004','test',2,NOW())");
        db.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(3,'store',4,NOW())");
        db.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address,delivery_fee," +
                "pay_amount,escrow_status,reviewed,create_time,pay_time,complete_time) " +
                "VALUES(7,'NO7',2,3,'store',4,'[]','{}',3,13,1,1,NOW(),NOW(),NOW())");
        db.update("INSERT INTO payment_transactions(id,order_id,user_id,channel,amount,out_trade_no,provider_transaction_id,status,create_time) " +
                "VALUES(9,7,2,'ALIPAY',13,'ALI7','provider7','SUCCESS',NOW())");
        when(riders.findById(8)).thenReturn(Optional.of(new com.example.takeout.model.Rider(8, 3, "rider", "13800000003",
                1, 0, 0, 1, 25000, 30.5, 114.3, "", "")));
        records = spy(new PaymentRecordDao(db)); records.insert(7, 2, 13d, "PAY", "ALIPAY", "SUCCESS", "2026-10-28 10:00:00");
        events = mock(DomainEventPublisher.class);
        gateway = mock(PaymentGateway.class); when(gateway.channel()).thenReturn("ALIPAY");
        doAnswer(invocation -> {
            String number = invocation.getArgument(1); BigDecimal amount = invocation.getArgument(2);
            BigDecimal previous = remoteRefunds.putIfAbsent(number, amount);
            if (previous != null) assertEquals(0, previous.compareTo(amount));
            channelCalls.add(number);
            if (loseChannelResponse.getAndSet(false)) throw new IllegalStateException("channel response lost after refund");
            return null;
        }).when(gateway).refund(anyString(), anyString(), any(), any());
        attempts = new ExternalRefundAttemptService(db, manager, new ObjectMapper());
        PaymentProperties properties = new PaymentProperties(); properties.setRealEnabled(true); properties.setSandbox(false);
        properties.getAlipay().setGatewayUrl("https://openapi.alipay.com/gateway.do");
        properties.getAlipay().setAppPrivateKey("test"); properties.getAlipay().setPublicKey("test");
        properties.getAlipay().setNotifyUrl("https://callback.example/api/payment/alipay/notify");
        payments = new ExternalPaymentService(properties, List.of(gateway), new PaymentTransactionDao(db), new OrderDao(db), records, events);
        payments.configureRefundAttempts(attempts);
        ReflectionTestUtils.invokeMethod(payments, "configureTransactions", new TransactionTemplate(manager));
        var salesTarget = new AfterSalesService(new OrderDao(db), new StoreDao(db), new RefundDao(db), new AfterSalesDao(db),
                payments, records, events, new ObjectMapper());
        salesTarget.configureRefundAttempts(attempts); sales = transactional(salesTarget);
        var orderTarget = new OrderService(new OrderDao(db), new StoreDao(db), mock(GoodsDao.class), mock(AddressDao.class),
                new CouponDao(db), mock(ReviewDao.class), new UserDao(db), new RefundDao(db), new ObjectMapper(),
                mock(CartItemMapper.class), riders, mock(GoodsSpecDao.class), mock(SeckillDao.class),
                mock(HotDataCacheService.class), events, mock(ObjectProvider.class), records);
        orderTarget.configureRefundAttempts(attempts); orderTarget.configureAfterSales(sales);
        orderTarget.configureTransactions(new TransactionTemplate(manager));
        ReflectionTestUtils.setField(orderTarget, "externalPaymentService", payments); orders = transactional(orderTarget);
        var adminTarget = new AdminService(new StoreDao(db), new OrderDao(db), new UserDao(db), mock(GoodsDao.class),
                new RefundDao(db), orders, mock(AdminStatsDao.class), mock(HotDataCacheService.class), events, records);
        adminTarget.configureRefundAttempts(attempts); admins = transactional(adminTarget);
        recovery = new ExternalRefundRecoveryJob(attempts, provider(sales), provider(orders), provider(payments));
    }

    @AfterEach
    void cleanup() {
        if (source != null) source.close();
        if (database != null) admin.execute("DROP DATABASE " + database);
    }

    @Test
    void successfulChannelRefundSurvivesLocalEventRollbackAndCannotBeRejected() {
        long refund = sales.apply(2, 7, "OTHER", "餐损", "apply", new BigDecimal("5.00"), List.of()).id();
        failEventOnce(DomainEventPublisher.ORDER_REFUNDED);
        assertThrows(IllegalStateException.class, () -> sales.approve(refund));
        assertEquals("PENDING", text("SELECT status FROM refund_records"));
        assertEquals("CONFIRMED", text("SELECT status FROM external_refund_attempts"));
        assertEquals(2, value("SELECT balance FROM users WHERE id=4"));
        assertEquals(0, value("SELECT COUNT(*) FROM after_sales_ledger"));
        assertThrows(BizException.class, () -> sales.reject(refund, "不能核实"));
        recovery.recover(); recovery.recover();
        assertEquals("REFUNDED", text("SELECT status FROM refund_records"));
        assertEquals("DONE", text("SELECT status FROM external_refund_attempts"));
        assertEquals(1, remoteRefunds.size()); assertEquals(1, channelCalls.size());
        assertEquals(1, value("SELECT COUNT(*) FROM after_sales_ledger"));
        assertEquals(3, value("SELECT debt_amount FROM after_sales_ledger"));
        assertEquals(5, value("SELECT SUM(amount) FROM payment_records WHERE type='REFUND'"));
        assertEquals(0, value("SELECT balance FROM users WHERE id=2"), "External refunds never credit the local wallet");
    }

    @Test
    void balanceRefundStillAllowsOrdinaryRejectionWithoutAnExternalIntent() {
        db.update("DELETE FROM payment_transactions");
        long refund = sales.apply(2, 7, "OTHER", "餐损", "balance", new BigDecimal("5.00"), List.of()).id();
        sales.reject(refund, "无法核实");
        assertEquals("REJECTED", text("SELECT status FROM refund_records"));
        assertEquals(0, value("SELECT COUNT(*) FROM external_refund_attempts"));
        assertEquals(0, remoteRefunds.size());
    }

    @Test
    void uncertainChannelOutcomeRetriesTheSameNumberAndBooksMoneyOnlyOnce() {
        long refund = sales.apply(2, 7, "OTHER", "餐损", "apply", new BigDecimal("5.00"), List.of()).id();
        loseChannelResponse.set(true);
        assertThrows(IllegalStateException.class, () -> sales.approve(refund));
        assertEquals("REQUESTED", text("SELECT status FROM external_refund_attempts"));
        assertThrows(BizException.class, () -> sales.reject(refund, "不能核实"));
        recovery.recover();
        assertEquals(2, channelCalls.size()); assertEquals(channelCalls.getFirst(), channelCalls.getLast());
        assertEquals(1, remoteRefunds.size()); assertEquals("DONE", text("SELECT status FROM external_refund_attempts"));
        assertEquals(5, value("SELECT SUM(amount) FROM payment_records WHERE type='REFUND'"));
    }

    @Test
    void cancellationRecoveryPreservesUserSourceAndUsedCouponAndBlocksFulfillment() { cancellation("USER"); }

    @Test
    void cancellationRecoveryPreservesAdminSourceAndReturnsCoupon() { cancellation("ADMIN"); }

    @Test
    void cancellationRecoveryPreservesMerchantSourceAndReturnsCoupon() { cancellation("MERCHANT"); }

    private void cancellation(String sourceKind) {
        db.update("UPDATE orders SET status=1,escrow_status=0,reviewed=0,coupon_id=6 WHERE id=7");
        db.update("INSERT INTO coupons(id,user_id,name,amount,status,expire_time,create_time) VALUES(6,2,'coupon',1,1,'2099-01-01 00:00:00',NOW())");
        failEventOnce(DomainEventPublisher.ORDER_CANCELLED);
        assertThrows(IllegalStateException.class, () -> {
            if ("USER".equals(sourceKind)) orders.cancelOrder(2, 7);
            else if ("ADMIN".equals(sourceKind)) orders.cancelOrderByAdmin(7);
            else orders.merchantReject(4, 7, "STORE_OVER_CAPACITY", "原备注", 0L, 0L);
        });
        assertEquals(1, value("SELECT status FROM orders WHERE id=7"));
        assertEquals(1, value("SELECT status FROM coupons WHERE id=6"));
        assertEquals("CONFIRMED", text("SELECT status FROM external_refund_attempts"));
        assertThrows(BizException.class, () -> orders.merchantFlow(4, 7, "accept"));
        assertThrows(BizException.class, () -> admins.orderFlow(7, "accept"));
        assertEquals(409, assertThrows(BizException.class, () -> orders.riderGrab(8, 7)).getCode());
        assertEquals(409, assertThrows(BizException.class, () -> orders.riderPickup(8, 7)).getCode());
        assertEquals(409, assertThrows(BizException.class, () -> orders.riderDeliver(8, 7)).getCode());
        recovery.recover(); recovery.recover();
        assertEquals(5, value("SELECT status FROM orders WHERE id=7"));
        assertEquals(2, value("SELECT escrow_status FROM orders WHERE id=7"));
        assertEquals(sourceKind, text("SELECT cancel_source FROM orders WHERE id=7"));
        assertEquals("USER".equals(sourceKind) ? 1 : 0, value("SELECT status FROM coupons WHERE id=6"));
        assertEquals("DONE", text("SELECT status FROM external_refund_attempts"));
        assertEquals(1, value("SELECT COUNT(*) FROM payment_records WHERE type='REFUND'"));
        assertEquals(1, remoteRefunds.size()); assertEquals(1, channelCalls.size());
    }

    @Test
    void latePaymentRecoveryUsesVerifiedIdentityAndRestoresBothFinancialFacts() {
        db.update("DELETE FROM payment_records");
        db.update("UPDATE orders SET status=5,escrow_status=0 WHERE id=7");
        db.update("UPDATE payment_transactions SET status='CLOSED',provider_transaction_id=NULL WHERE id=9");
        when(gateway.verifyNotification(anyString(), anyMap())).thenReturn(new PaymentGateway.VerifiedNotice("ALI7", "verified-provider7", 1300, "CNY", true));
        doThrow(new IllegalStateException("refund ledger insert failed")).doCallRealMethod().when(records)
                .insert(eq(7L), eq(2L), eq(13d), eq("REFUND"), eq("ALIPAY"), eq("SUCCESS"), anyString());
        assertThrows(IllegalStateException.class, () -> payments.acceptNotification("ALIPAY", "verified", Map.of()));
        assertEquals(0, value("SELECT COUNT(*) FROM payment_records"));
        assertEquals("CONFIRMED", text("SELECT status FROM external_refund_attempts"));
        assertEquals("verified-provider7", text("SELECT provider_transaction_id FROM external_refund_attempts"));
        recovery.recover(); recovery.recover();
        assertEquals("LATE_REFUNDED", text("SELECT status FROM payment_transactions"));
        assertEquals("DONE", text("SELECT status FROM external_refund_attempts"));
        assertEquals(2, value("SELECT COUNT(*) FROM payment_records"));
        assertEquals(0, value("SELECT SUM(CASE WHEN type='PAY' THEN amount ELSE -amount END) FROM payment_records"));
        assertEquals(1, channelCalls.size()); assertEquals(5, value("SELECT status FROM orders WHERE id=7"));
    }

    private void failEventOnce(String event) {
        doThrow(new IllegalStateException("outbox insert failed")).doNothing().when(events).publish(eq(event), anyLong(), anyMap());
    }
    private int value(String sql) { return db.queryForObject(sql, Integer.class); }
    private String text(String sql) { return db.queryForObject(sql, String.class); }
    private <T> T transactional(T target) {
        var factory = new ProxyFactory(target);
        factory.addAdvice(new TransactionInterceptor(manager, new AnnotationTransactionAttributeSource()));
        return (T) factory.getProxy();
    }
    private static <T> ObjectProvider<T> provider(T value) {
        ObjectProvider<T> provider = mock(ObjectProvider.class); when(provider.getObject()).thenReturn(value); return provider;
    }
}
