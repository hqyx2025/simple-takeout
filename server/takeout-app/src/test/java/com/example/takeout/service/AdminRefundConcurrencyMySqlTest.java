package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AdminStatsDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Order;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.service.mq.DomainEventPublisher;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;

import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/** Approval and rejection must serialize on the same refund, including their money side effects. */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class AdminRefundConcurrencyMySqlTest {

    @Test
    void approvalPreventsConcurrentRejectionFromOverwritingTheRefund() throws Exception {
        assertSingleDecision(true);
    }

    @Test
    void rejectionPreventsConcurrentApprovalFromRefundingMoneyOrStock() throws Exception {
        assertSingleDecision(false);
    }

    private void assertSingleDecision(boolean approveFirst) throws Exception {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1")
                + ":" + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        String database = "takeout_refund_" + UUID.randomUUID().toString().replace("-", "");
        JdbcTemplate admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        admin.execute("CREATE DATABASE `" + database + "`");
        try {
            var source = new DriverManagerDataSource(base + database + options, username, password);
            new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
            JdbcTemplate jdbc = new JdbcTemplate(source);
            jdbc.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address," +
                    "pay_amount,create_time) VALUES(7,'NO7',2,3,'store',6,'[]','{}',13,NOW())");
            jdbc.update("INSERT INTO refund_records(id,order_id,user_id,merchant_id,amount,apply_time) " +
                    "VALUES(9,7,2,4,13,NOW())");

            CountDownLatch firstLocked = new CountDownLatch(1);
            CountDownLatch secondAttempted = new CountDownLatch(1);
            CountDownLatch releaseFirst = new CountDownLatch(1);
            AtomicInteger lockAttempts = new AtomicInteger();
            RefundDao refunds = spy(new RefundDao(jdbc));
            doAnswer(invocation -> {
                if (lockAttempts.incrementAndGet() == 1) {
                    Object record = invocation.callRealMethod();
                    firstLocked.countDown();
                    assertTrue(releaseFirst.await(10, TimeUnit.SECONDS));
                    return record;
                }
                secondAttempted.countDown();
                return invocation.callRealMethod();
            }).when(refunds).findByIdForUpdate(9);

            OrderService orders = mock(OrderService.class);
            var target = new AdminService(mock(StoreDao.class), new OrderDao(jdbc), mock(UserDao.class),
                    mock(GoodsDao.class), refunds, orders, mock(AdminStatsDao.class),
                    mock(HotDataCacheService.class), mock(DomainEventPublisher.class), mock(PaymentRecordDao.class));
            var proxy = new ProxyFactory(target);
            proxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(source),
                    new AnnotationTransactionAttributeSource()));
            AdminService service = (AdminService) proxy.getProxy();

            try (var executor = Executors.newFixedThreadPool(2)) {
                var first = executor.submit(() -> decide(service, approveFirst));
                assertTrue(firstLocked.await(10, TimeUnit.SECONDS));
                var second = executor.submit(() -> decide(service, !approveFirst));
                try {
                    assertTrue(secondAttempted.await(10, TimeUnit.SECONDS));
                    assertFalse(second.isDone(), "The opposing decision must wait for the refund row lock");
                } finally {
                    releaseFirst.countDown();
                }
                assertEquals(approveFirst ? "REFUNDED" : "REJECTED", first.get(15, TimeUnit.SECONDS).status());
                ExecutionException loser = assertThrows(ExecutionException.class,
                        () -> second.get(15, TimeUnit.SECONDS));
                assertInstanceOf(BizException.class, loser.getCause());
                assertEquals("该退款申请已处理", loser.getCause().getMessage());
            } finally {
                releaseFirst.countDown();
            }

            assertEquals(approveFirst ? "REFUNDED" : "REJECTED",
                    jdbc.queryForObject("SELECT status FROM refund_records WHERE id=9", String.class));
            assertEquals(approveFirst ? 2 : 0,
                    jdbc.queryForObject("SELECT escrow_status FROM orders WHERE id=7", Integer.class));
            assertEquals(approveFirst ? 6 : 4,
                    jdbc.queryForObject("SELECT status FROM orders WHERE id=7", Integer.class));
            verify(orders, times(approveFirst ? 1 : 0)).refundOrderPayment(any(Order.class));
            verify(orders, never()).rollbackStock(any(Order.class));
            assertFalse(new RefundDao(jdbc).updateStatus(9, "PENDING", "", ""),
                    "A completed refund must not be overwritten by an unconditional status update");
        } finally {
            admin.execute("DROP DATABASE `" + database + "`");
        }
    }

    private RefundRecord decide(AdminService service, boolean approve) {
        return approve ? service.approveRefund(9) : service.rejectRefund(9, "无法核实");
    }
}
