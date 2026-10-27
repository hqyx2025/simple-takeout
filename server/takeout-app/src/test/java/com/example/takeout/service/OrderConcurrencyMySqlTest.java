package com.example.takeout.service;

import com.baomidou.mybatisplus.core.MybatisConfiguration;
import com.baomidou.mybatisplus.extension.spring.MybatisSqlSessionFactoryBean;
import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.Order;
import com.example.takeout.model.Review;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.mybatis.spring.SqlSessionTemplate;
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
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.AdditionalAnswers.delegatesTo;
import static org.mockito.ArgumentMatchers.*;

/**
 * Opt-in real MySQL regression. Creates and drops only its own random database;
 * never writes to takeout. Set TAKEOUT_MYSQL_CONCURRENCY_TEST=1 and DB credentials.
 */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class OrderConcurrencyMySqlTest {
    @Test @EnabledIfEnvironmentVariable(named = "TAKEOUT_TEST_REDIS_PORT", matches = "\\d+")
    void loginCollationVariantsAndOwnAccountCannotBypassRealSqlAndRedisBudgets() {
        jdbc.execute("ALTER TABLE users MODIFY phone VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL");
        String victim = "13800000001", own = "13800000002";
        var users = spy(new UserDao(jdbc));
        var jwt = mock(com.example.takeout.security.JwtUtil.class);
        when(jwt.generateToken(anyLong(), anyInt(), anyString())).thenReturn("test-token");
        String hash = com.example.takeout.security.PasswordUtil.hash("test-own-password");
        jdbc.update("UPDATE users SET password = ?, role = 2 WHERE id = 1", hash);
        jdbc.update("UPDATE users SET password = ? WHERE id = 2", hash);
        var auth = new AuthService(users, jwt);
        var connection = new org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory(
                "127.0.0.1", Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        connection.afterPropertiesSet(); connection.start();
        try {
            var redis = new org.springframework.data.redis.core.StringRedisTemplate(connection);
            ObjectProvider<org.springframework.data.redis.core.StringRedisTemplate> provider = mock(ObjectProvider.class);
            when(provider.getIfAvailable()).thenReturn(redis);
            var limiter = new com.example.takeout.security.LoginRateLimiter(provider);
            var controller = new com.example.takeout.controller.AuthController(auth, limiter,
                    mock(com.example.takeout.security.TokenRevocationService.class), mock(RefreshTokenService.class),
                    mock(SmsVerificationService.class), mock(PushTokenService.class));
            int source = 1;
            for (char ignored : new char[]{0x200b, 0xad, 0x200c, 0x200d, 0x2060, 0xfeff, 0}) {
                for (int position = 0; position <= 11; position++) {
                    String variant = victim.substring(0, position) + ignored + victim.substring(position);
                    assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE phone = ?", Integer.class, variant));
                    var http = new org.springframework.mock.web.MockHttpServletRequest();
                    http.setRemoteAddr("192.0.2." + source++);
                    assertEquals(400, assertThrows(BizException.class, () -> controller.login(
                            new com.example.takeout.controller.AuthController.LoginRequest(variant, "wrong", "ADMIN"), http)).getCode());
                }
            }
            verify(users, never()).findByPhone(anyString());
            var http = new org.springframework.mock.web.MockHttpServletRequest();
            http.setRemoteAddr("198.51.100.10");
            var guess = new com.example.takeout.controller.AuthController.LoginRequest(victim, "wrong", "ADMIN");
            for (int i = 0; i < 9; i++) assertEquals(400, assertThrows(BizException.class,
                    () -> controller.login(guess, http)).getCode());
            controller.login(new com.example.takeout.controller.AuthController.LoginRequest(own, "test-own-password", "USER"), http);
            http.setRemoteAddr("198.51.100.11");
            assertEquals(400, assertThrows(BizException.class, () -> controller.login(guess, http)).getCode());
            http.setRemoteAddr("198.51.100.12");
            assertEquals(429, assertThrows(BizException.class, () -> controller.login(guess, http)).getCode());
            http.setRemoteAddr("198.51.100.10");
            assertEquals(400, assertThrows(BizException.class, () -> controller.login(
                    new com.example.takeout.controller.AuthController.LoginRequest("13800000003", "wrong", "USER"), http)).getCode());
            assertEquals(429, assertThrows(BizException.class, () -> controller.login(
                    new com.example.takeout.controller.AuthController.LoginRequest(own, "test-own-password", "USER"), http)).getCode());
            new com.example.takeout.config.SchemaMigration(jdbc).run(null);
            assertEquals("utf8mb4_0900_bin", jdbc.queryForObject("SELECT COLLATION_NAME FROM information_schema.COLUMNS "
                    + "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'phone'", String.class));
            for (char ignored : new char[]{0x200b, 0xad, 0x200c, 0x200d, 0x2060, 0xfeff, 0})
                assertTrue(users.findByPhone(victim + ignored).isEmpty());
        } finally { connection.destroy(); }
    }

    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private String database;
    private OrderService service;
    private AdminService adminService;
    private PaymentRecordDao paymentRecords;
    private OutboxEventDao outbox;
    private HotDataCacheService cache;
    private CartItemMapper cartItems;

    @BeforeEach
    void setUp() throws Exception {
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
        var cartFactory = new MybatisSqlSessionFactoryBean();
        cartFactory.setDataSource(source);
        cartFactory.setConfiguration(new MybatisConfiguration());
        var cartSessions = cartFactory.getObject();
        cartSessions.getConfiguration().addMapper(CartItemMapper.class);
        cartItems = new SqlSessionTemplate(cartSessions).getMapper(CartItemMapper.class);
        var transactions = new TransactionTemplate(new DataSourceTransactionManager(source));
        paymentRecords = spy(new PaymentRecordDao(jdbc));
        outbox = spy(new OutboxEventDao(jdbc, transactions));
        cache = mock(HotDataCacheService.class);
        var specs = new GoodsSpecDao(jdbc);
        var target = new OrderService(new OrderDao(jdbc), new StoreDao(jdbc), new GoodsDao(jdbc, specs),
                new AddressDao(jdbc), new CouponDao(jdbc), new ReviewDao(jdbc), new UserDao(jdbc),
                new RefundDao(jdbc), new ObjectMapper(), cartItems, new RiderDao(jdbc),
                specs, new SeckillDao(jdbc), cache,
                new DomainEventPublisher(outbox, mock(ObjectProvider.class), new ObjectMapper()),
                mock(ObjectProvider.class), paymentRecords);
        target.configureTransactions(transactions);
        var proxy = new ProxyFactory(target);
        proxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(source),
                new AnnotationTransactionAttributeSource()));
        service = (OrderService) proxy.getProxy();
        var adminTarget = new AdminService(new StoreDao(jdbc), new OrderDao(jdbc), new UserDao(jdbc),
                new GoodsDao(jdbc, specs), new RefundDao(jdbc), service, mock(AdminStatsDao.class), cache,
                new DomainEventPublisher(outbox, mock(ObjectProvider.class), new ObjectMapper()), paymentRecords);
        var adminProxy = new ProxyFactory(adminTarget);
        adminProxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(source),
                new AnnotationTransactionAttributeSource()));
        adminService = (AdminService) adminProxy.getProxy();
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time,latitude,longitude) VALUES(10,'test',99,'2026-01-01 00:00:00',30.5,114.3)");
        for (int id = 1; id <= 8; id++) {
            jdbc.update("INSERT INTO users(id,username,phone,password,balance,create_time) VALUES(?,?,?,'test',1000,?)",
                    id, "user" + id, "1380000000" + id, "2026-01-01 00:00:00");
            jdbc.update("INSERT INTO addresses(id,user_id,name,phone,detail,create_time,latitude,longitude) VALUES(?,?,'test','test','test',?,30.5,114.3)",
                    id, id, "2026-01-01 00:00:00");
            jdbc.update("INSERT INTO coupons(id,user_id,name,amount,expire_time,create_time) VALUES(?,?,'test',1,'2099-01-01 00:00:00',?)",
                    id, id, "2026-01-01 00:00:00");
        }
        jdbc.update("UPDATE users SET payment_password_hash = ? WHERE id = 1",
                com.example.takeout.security.PaymentPasswordUtil.hash("135790"));
        jdbc.update("INSERT INTO users(id,username,phone,password,balance,role,create_time) " +
                        "VALUES(99,'merchant','13900000099','test',1000,1,'2026-01-01 00:00:00')");
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
    void expiredOutboxOwnerCannotAcknowledgeOrRescheduleNewLease() {
        long id=outbox.insert("ORDER_CREATED",0,"{}","2026-10-27 00:00:00");long now=System.currentTimeMillis();
        assertEquals(1,outbox.claimPending(10,"old-owner",now,now+10).size());
        assertEquals(1,outbox.claimPending(10,"new-owner",now+20,now+30000).size());
        outbox.markSent(id,"old-owner");outbox.markRetry(id,"old-owner",0);
        assertEquals(0,outbox.findById(id).orElseThrow().status());
        assertEquals(0,outbox.findById(id).orElseThrow().retryCount());
        outbox.markRetry(id,"new-owner",3);
        assertEquals(1,outbox.findById(id).orElseThrow().retryCount());
        assertTrue(outbox.claimPending(10,"third-owner",now+100,now+30000).isEmpty());
    }

    private UploadService uploads(com.example.takeout.service.thirdparty.ObjectStorage storage, long perUser, long total) {
        var target = new UploadService(jdbc, storage, new com.example.takeout.security.LoginRateLimiter(mock(ObjectProvider.class)), perUser, total);
        var proxy = new ProxyFactory(target);
        proxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(jdbc.getDataSource()),
                new AnnotationTransactionAttributeSource()));
        return (UploadService) proxy.getProxy();
    }

    private org.springframework.mock.web.MockMultipartFile uploadImage() {
        return new org.springframework.mock.web.MockMultipartFile("file", "photo.jpg", "image/jpeg",
                new byte[]{(byte)255, (byte)216, (byte)255});
    }

    @Test void concurrentUploadInstancesShareAccountQuota() throws Exception {
        AtomicInteger stored = new AtomicInteger();
        var storage = (com.example.takeout.service.thirdparty.ObjectStorage) file -> { stored.incrementAndGet(); return "/uploads/test.jpg"; };
        List<UploadService> instances = List.of(uploads(storage, 8, 100), uploads(storage, 8, 100));
        runTogether(16, index -> {
            try { instances.get(index % 2).store(7, uploadImage()); }
            catch (BizException e) { assertEquals(429, e.getCode()); }
        });
        assertEquals(2, stored.get());
        assertEquals(6L, jdbc.queryForObject("SELECT used_bytes FROM upload_usage WHERE user_id=7", Long.class));
        assertEquals(6L, jdbc.queryForObject("SELECT used_bytes FROM upload_usage WHERE user_id=0", Long.class));
    }

    @Test void globalUploadQuotaCannotBeBypassedByChangingAccounts() throws Exception {
        AtomicInteger stored = new AtomicInteger();
        var service = uploads(file -> { stored.incrementAndGet(); return "/uploads/test.jpg"; }, 8, 8);
        runTogether(16, index -> {
            try { service.store(index % 8 + 1, uploadImage()); }
            catch (BizException e) { assertEquals(429, e.getCode()); }
        });
        assertEquals(2, stored.get());
        assertEquals(6L, jdbc.queryForObject("SELECT used_bytes FROM upload_usage WHERE user_id=0", Long.class));
    }

    @Test void failedUserReservationAndStorageFailureBothRollBackGlobalQuota() {
        jdbc.update("INSERT INTO upload_usage(user_id,used_bytes) VALUES(0,11),(7,7)");
        AtomicInteger writes = new AtomicInteger();
        var exhausted = uploads(file -> { writes.incrementAndGet(); return "/uploads/test.jpg"; }, 8, 100);
        assertEquals(429, assertThrows(BizException.class, () -> exhausted.store(7, uploadImage())).getCode());
        assertEquals(0, writes.get());
        assertEquals(11L, jdbc.queryForObject("SELECT used_bytes FROM upload_usage WHERE user_id=0", Long.class));
        var failing = uploads(file -> { throw new IllegalStateException("test storage failure"); }, 100, 100);
        assertThrows(IllegalStateException.class, () -> failing.store(7, uploadImage()));
        assertEquals(11L, jdbc.queryForObject("SELECT used_bytes FROM upload_usage WHERE user_id=0", Long.class));
        assertEquals(7L, jdbc.queryForObject("SELECT used_bytes FROM upload_usage WHERE user_id=7", Long.class));
    }

    @Test void employeeFromAnotherStoreSurvivesAuthorizedStoreDeletionAttempt() {
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(11,'other',98,NOW())");
        jdbc.update("INSERT INTO employees(id,store_id,user_id,role_name,status,create_time) VALUES(1,11,2,'clerk',1,NOW())");
        var stores = new StoreService(new StoreDao(jdbc), mock(GoodsDao.class), mock(GoodsSpecDao.class),
                mock(SeckillDao.class), new ObjectMapper(), mock(HotDataCacheService.class), new EmployeeDao(jdbc));
        assertEquals(404, assertThrows(BizException.class, () -> stores.removeStoreEmployee(99, 10, 1)).getCode());
        assertEquals(1, count("SELECT COUNT(*) FROM employees WHERE id=1 AND store_id=11"));
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
        assertEquals(8, count("SELECT COUNT(*) FROM users WHERE id BETWEEN 1 AND 8 AND balance=1000"));
        assertEquals(192, count("SELECT COUNT(*) FROM outbox_events"));
    }

    @Test
    void sameRequestAcrossConcurrentTransactionsCreatesOnlyOneOrderWithoutRedis() throws Exception {
        var orderIds = java.util.concurrent.ConcurrentHashMap.<Long>newKeySet();
        runTogether(8, index -> {
            Order.OrderView replay = service.createOrder(1, 10, List.of(item(102, 300)), 1, 1, "",
                    List.of(), "", "same-request", List.of(), "");
            orderIds.add(replay.id());
        });
        assertEquals(1, orderIds.size());
        assertEquals(1, count("SELECT COUNT(*) FROM orders"));
        assertEquals(1, count("SELECT COUNT(*) FROM order_create_requests"));
        assertEquals(orderIds.iterator().next().longValue(),
                jdbc.queryForObject("SELECT order_id FROM order_create_requests", Long.class));
        assertEquals(999, count("SELECT stock FROM goods WHERE id=102"));
        assertEquals(999, count("SELECT stock FROM goods_specs WHERE id=300"));
        assertEquals(1, count("SELECT status FROM coupons WHERE id=1"));
    }

    @Test
    void failedRequestRollsBackReservationAndKeysAreIsolatedByAccount() {
        assertThrows(BizException.class, () -> service.createOrder(1, 10, List.of(), 1, 0, "",
                List.of(), "", "retry-key", List.of(), ""));
        assertEquals(0, count("SELECT COUNT(*) FROM order_create_requests"));

        service.createOrder(1, 10, List.of(item(102, 300)), 1, 0, "",
                List.of(), "", "retry-key", List.of(), "");
        service.createOrder(2, 10, List.of(item(102, 300)), 2, 0, "",
                List.of(), "", "retry-key", List.of(), "");
        // A committed key returns the original order after the old Redis window has expired.
        jdbc.update("UPDATE order_create_requests SET create_time='2020-01-01 00:00:00'");
        Order.OrderView replay = service.createOrder(1, 10, List.of(item(102, 300)), 1, 0, "",
                List.of(), "", "retry-key", List.of(), "");
        assertEquals(jdbc.queryForObject("SELECT order_id FROM order_create_requests WHERE user_id=1", Long.class),
                replay.id());
        assertEquals(2, count("SELECT COUNT(*) FROM orders"));
        assertEquals(2, count("SELECT COUNT(*) FROM order_create_requests"));
        assertEquals(998, count("SELECT stock FROM goods WHERE id=102"));
    }

    @Test
    void simultaneousPayAndCancelNeverDoubleRefundOrLoseStock() throws Exception {
        for (int iteration = 0; iteration < 12; iteration++) {
            long id = service.createOrder(1, 10, List.of(item(102, 300)), 1, 0, "").id();
            runTogether(3, index -> {
                try {
                    if (index == 0) service.payOrder(1, id, "BALANCE", "QR", "135790");
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

    @Test
    void concurrentMerchantRejectReplaysOneRefundAndOneResourceRollback() throws Exception {
        long id = service.createOrder(1, 10, List.of(item(102, 300)), 1, 1, "").id();
        service.payOrder(1, id, "BALANCE", "QR", "135790");

        var returnedOrderIds = java.util.concurrent.ConcurrentHashMap.<Long>newKeySet();
        runTogether(8, index -> returnedOrderIds.add(
                service.merchantReject(99, id, "OTHER", "internal note", null, null).id()));

        assertEquals(java.util.Set.of(id), returnedOrderIds);
        Order.OrderView rejected = service.orderDetail(id);
        assertEquals(5, rejected.status());
        assertEquals(2, rejected.escrowStatus());
        assertEquals("MERCHANT", rejected.cancelSource());
        assertEquals("OTHER", rejected.cancelReasonCode());
        assertEquals(1000, count("SELECT balance FROM users WHERE id=1"));
        assertEquals(1000, count("SELECT stock FROM goods WHERE id=102"));
        assertEquals(1000, count("SELECT stock FROM goods_specs WHERE id=300"));
        assertEquals(0, count("SELECT status FROM coupons WHERE id=1"));
        assertEquals(1, count("SELECT COUNT(*) FROM payment_records WHERE type='REFUND' AND order_id=" + id));
        assertEquals(1, count("SELECT COUNT(*) FROM outbox_events WHERE event_type='ORDER_CANCELLED' AND order_id=" + id));
    }

    private Order.OrderItem item(long goodsId, long specId) {
        return new Order.OrderItem(goodsId, "test", 0, 1, "", specId, "", 0);
    }

    @Test
    void differentGoodsCanBeAddedToEmptyCartConcurrentlyThroughAllQuantityEntrypoints() throws Exception {
        var source = jdbc.getDataSource();
        var factory = new MybatisSqlSessionFactoryBean();
        factory.setDataSource(source);
        factory.setConfiguration(new MybatisConfiguration());
        var sessions = factory.getObject();
        sessions.getConfiguration().addMapper(CartItemMapper.class);
        var realMapper = new SqlSessionTemplate(sessions).getMapper(CartItemMapper.class);
        var specs = new GoodsSpecDao(jdbc);

        for (int entrypoint = 0; entrypoint < 4; entrypoint++) {
            jdbc.update("DELETE FROM cart_items");
            var bothRowsRead = new CountDownLatch(2);
            var mapper = mock(CartItemMapper.class, delegatesTo(realMapper));
            doAnswer(invocation -> {
                var row = realMapper.selectOne(invocation.getArgument(0));
                assertNull(row);
                // Force both transactions to finish the missing-row SELECT before either INSERT.
                // REPEATABLE_READ acquires overlapping gap locks here and then deadlocks.
                bothRowsRead.countDown();
                assertTrue(bothRowsRead.await(10, TimeUnit.SECONDS));
                return row;
            }).when(mapper).selectOne(any());
            var target = new CartService(mapper, new GoodsDao(jdbc, specs), new StoreDao(jdbc), specs);
            var proxy = new ProxyFactory(target);
            proxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(source),
                    new AnnotationTransactionAttributeSource()));
            var cart = (CartService) proxy.getProxy();
            int operation = entrypoint;

            runTogether(2, index -> {
                long goodsId = 100 + index;
                int quantity = 2 + index;
                switch (operation) {
                    case 0 -> cart.add(1, goodsId, quantity);
                    case 1 -> cart.add(1, goodsId, 0, quantity);
                    case 2 -> cart.setQuantity(1, goodsId, quantity);
                    case 3 -> cart.setQuantity(1, goodsId, 0, quantity);
                    default -> throw new AssertionError("Unknown cart entrypoint");
                }
            });

            assertEquals(2, count("SELECT COUNT(*) FROM cart_items WHERE user_id=1"));
            assertEquals(2, count("SELECT quantity FROM cart_items WHERE user_id=1 AND goods_id=100 AND spec_id=0"));
            assertEquals(3, count("SELECT quantity FROM cart_items WHERE user_id=1 AND goods_id=101 AND spec_id=0"));
        }
        assertEquals(3, count("SELECT COUNT(*) FROM goods WHERE stock=1000"));
    }

    @Test
    void directOrderDoesNotDeleteMatchingCartSku() {
        jdbc.update("INSERT INTO goods_specs(id,goods_id,name,price,stock,create_time) " +
                "VALUES(301,102,'small',10,1000,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(11,'other-store',99,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO goods(id,store_id,name,price,stock,create_time) " +
                "VALUES(200,11,'other-goods',10,1000,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO cart_items(user_id,goods_id,spec_id,quantity,create_time,update_time) " +
                "VALUES(1,102,300,1,NOW(),NOW()),(1,102,301,1,NOW(),NOW())," +
                "(1,200,0,1,NOW(),NOW()),(2,102,300,1,NOW(),NOW())");

        service.createOrder(1, 10, List.of(item(102, 300)), 1, 0, "");

        assertEquals(1, count("SELECT COUNT(*) FROM cart_items WHERE user_id=1 AND goods_id=102 AND spec_id=300"));
        assertEquals(1, count("SELECT COUNT(*) FROM cart_items WHERE user_id=1 AND goods_id=102 AND spec_id=301"));
        assertEquals(1, count("SELECT COUNT(*) FROM cart_items WHERE user_id=1 AND goods_id=200 AND spec_id=0"));
        assertEquals(1, count("SELECT COUNT(*) FROM cart_items WHERE user_id=2 AND goods_id=102 AND spec_id=300"));
    }

    @Test
    void cartCheckoutLocksAndConsumesExactLocalSkuSetAcrossStores() {
        jdbc.update("INSERT INTO goods_specs(id,goods_id,name,price,stock,create_time) " +
                "VALUES(301,102,'small',10,1000,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(11,'other-store',99,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO goods(id,store_id,name,price,stock,create_time) " +
                "VALUES(200,11,'other-goods',10,1000,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO cart_items(user_id,goods_id,spec_id,quantity,create_time,update_time) " +
                "VALUES(1,102,300,1,NOW(),NOW()),(1,102,301,2,NOW(),NOW()),(1,200,0,4,NOW(),NOW())");

        Order.OrderView created = service.createOrder(1, 10, List.of(
                        item(102, 300),
                        new Order.OrderItem(102, "test", 0, 2, "", 301, "", 0)),
                1, 0, "", List.of(102L, 102L, 200L));

        assertEquals(30.0, created.goodsAmount(), 0.001);
        assertEquals(0, count("SELECT COUNT(*) FROM cart_items WHERE user_id=1 AND goods_id=102"));
        assertEquals(1, count("SELECT COUNT(*) FROM cart_items WHERE user_id=1 AND goods_id=200 AND spec_id=0"));
        assertEquals(997, count("SELECT stock FROM goods WHERE id=102"));
        assertEquals(999, count("SELECT stock FROM goods_specs WHERE id=300"));
        assertEquals(998, count("SELECT stock FROM goods_specs WHERE id=301"));
    }

    @Test
    void multiStoreCheckoutCreatesSecondOrderAfterFirstStoreRowsWereDeleted() {
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time,latitude,longitude) VALUES(11,'other-store',99,'2026-01-01 00:00:00',30.5,114.3)");
        jdbc.update("INSERT INTO goods(id,store_id,name,price,stock,create_time) " +
                "VALUES(200,11,'other-goods',10,1000,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO cart_items(user_id,goods_id,spec_id,quantity,create_time,update_time) " +
                "VALUES(1,102,300,1,NOW(),NOW()),(1,200,0,1,NOW(),NOW())");
        List<Long> allSelectedGoods = List.of(102L, 200L);

        service.createOrder(1, 10, List.of(item(102, 300)), 1, 0, "", allSelectedGoods);
        service.createOrder(1, 11,
                List.of(new Order.OrderItem(200, "other-goods", 0, 1, "", 0, "", 0)),
                1, 0, "", allSelectedGoods);

        assertEquals(2, count("SELECT COUNT(*) FROM orders"));
        assertEquals(0, count("SELECT COUNT(*) FROM cart_items WHERE user_id=1"));
    }

    @Test
    void concurrentCartQuantityChangeIsNeverLostByCheckout() throws Exception {
        jdbc.update("INSERT INTO cart_items(user_id,goods_id,spec_id,quantity,create_time,update_time) " +
                "VALUES(1,102,300,1,NOW(),NOW())");
        var source = jdbc.getDataSource();
        var specs = new GoodsSpecDao(jdbc);
        var target = new CartService(cartItems, new GoodsDao(jdbc, specs), new StoreDao(jdbc), specs);
        var proxy = new ProxyFactory(target);
        proxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(source),
                new AnnotationTransactionAttributeSource()));
        var cart = (CartService) proxy.getProxy();
        AtomicInteger orderCreated = new AtomicInteger(-1);

        runTogether(2, index -> {
            if (index == 0) {
                try {
                    service.createOrder(1, 10, List.of(item(102, 300)), 1, 0, "", List.of(102L));
                    orderCreated.set(1);
                } catch (BizException changed) {
                    assertEquals("购物车商品已变化，请刷新后重试", changed.getMessage());
                    orderCreated.set(0);
                }
            } else {
                cart.setQuantity(1, 102, 300, 2);
            }
        });

        assertTrue(orderCreated.get() == 0 || orderCreated.get() == 1);
        assertEquals(2, count("SELECT quantity FROM cart_items WHERE user_id=1 AND goods_id=102 AND spec_id=300"));
        assertEquals(orderCreated.get(), count("SELECT COUNT(*) FROM orders"));
        assertEquals(1000 - orderCreated.get(), count("SELECT stock FROM goods WHERE id=102"));
        assertEquals(1000 - orderCreated.get(), count("SELECT stock FROM goods_specs WHERE id=300"));
    }

    @Test
    void unresolvedCreateRequestDistinguishesRecentAndHistoricalPlaceholders() {
        jdbc.update("INSERT INTO order_create_requests(user_id,request_key,order_id,create_time) " +
                "VALUES(1,'historical',NULL,'2020-01-01 00:00:00'),(2,'recent',NULL,NOW())");

        BizException historical = assertThrows(BizException.class, () -> service.createOrder(
                1, 10, List.of(item(102, 300)), 1, 0, "", List.of(), "", "historical", List.of(), ""));
        BizException recent = assertThrows(BizException.class, () -> service.createOrder(
                2, 10, List.of(item(102, 300)), 2, 0, "", List.of(), "", "recent", List.of(), ""));

        assertEquals("订单可能已提交，请在订单列表核对，不要重复下单", historical.getMessage());
        assertEquals("订单正在提交中，请稍后重试", recent.getMessage());
        assertEquals(0, count("SELECT COUNT(*) FROM orders"));
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
    void adminUserAndTimeoutCancellationReleaseTheSameReservationOnlyOnce() throws Exception {
        long id = service.createOrder(1, 10, List.of(item(102, 300)), 1, 1, "").id();
        jdbc.update("UPDATE orders SET create_time='2026-01-01 00:00:00' WHERE id=?", id);

        runTogether(3, index -> {
            if (index == 0) {
                service.cancelExpiredPendingOrders();
                return;
            }
            try {
                if (index == 1) service.cancelOrder(1, id);
                else adminService.orderFlow(id, "cancel");
            } catch (BizException alreadyCancelled) {
                assertTrue(alreadyCancelled.getMessage().contains("取消"));
            }
        });

        assertEquals(5, service.orderDetail(id).status());
        assertEquals(1000, count("SELECT stock FROM goods WHERE id=102"));
        assertEquals(1000, count("SELECT stock FROM goods_specs WHERE id=300"));
        assertEquals(0, count("SELECT status FROM coupons WHERE id=1"));
        assertEquals(1000, count("SELECT balance FROM users WHERE id=1"));
        assertEquals(0, count("SELECT COUNT(*) FROM payment_records"));
        assertEquals(1, count("SELECT COUNT(*) FROM outbox_events WHERE event_type='ORDER_CANCELLED'"));
    }

    @Test
    void adminAndUserCancellationCompeteWithPaymentWithoutDuplicatingFundsOrStock() throws Exception {
        long id = service.createOrder(1, 10, List.of(item(102, 300)), 1, 1, "").id();

        runTogether(8, index -> {
            try {
                if (index == 0) service.payOrder(1, id, "BALANCE", "QR", "135790");
                else if (index % 2 == 0) service.cancelOrder(1, id);
                else adminService.orderFlow(id, "cancel");
            } catch (BizException alreadyProcessed) {
                assertTrue(alreadyProcessed.getMessage().contains("取消")
                        || alreadyProcessed.getMessage().contains("状态"));
            }
        });

        assertEquals(5, service.orderDetail(id).status());
        assertEquals(1000, count("SELECT balance FROM users WHERE id=1"));
        assertEquals(1000, count("SELECT stock FROM goods WHERE id=102"));
        assertEquals(1000, count("SELECT stock FROM goods_specs WHERE id=300"));
        int payments = count("SELECT COUNT(*) FROM payment_records WHERE type='PAY'");
        assertTrue(payments == 0 || payments == 1);
        assertEquals(payments, count("SELECT COUNT(*) FROM payment_records WHERE type='REFUND'"));
        assertEquals(payments, count("SELECT status FROM coupons WHERE id=1"));
        assertEquals(1, count("SELECT COUNT(*) FROM outbox_events WHERE event_type='ORDER_CANCELLED'"));
    }

    @Test
    void adminCancellationRollsBackAllResourcesWhenEventWriteFails() {
        long id = service.createOrder(1, 10, List.of(item(100, 0)), 1, 1, "").id();
        doThrow(new CannotAcquireLockException("injected outbox failure"))
                .when(outbox).insert(eq(DomainEventPublisher.ORDER_CANCELLED), eq(id), anyString(), anyString());

        assertThrows(CannotAcquireLockException.class, () -> adminService.orderFlow(id, "cancel"));

        assertEquals(0, service.orderDetail(id).status());
        assertEquals(999, count("SELECT stock FROM goods WHERE id=100"));
        assertEquals(1, count("SELECT sold FROM seckills WHERE id=100"));
        assertEquals(1, count("SELECT COUNT(*) FROM seckill_orders"));
        assertEquals(1, count("SELECT status FROM coupons WHERE id=1"));
    }

    @Test
    void setmealSnapshotAndStoredItemAmountsMatchToTheCent() throws Exception {
        jdbc.update("INSERT INTO setmeals(id,store_id,name,price,create_time) VALUES(500,10,'three items',10,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO setmeal_items(setmeal_id,goods_id,goods_name,quantity) VALUES(500,100,'component',3)");
        var order = service.createOrder(1, 10, List.of(), 1, 0, "", List.of(), "", "",
                List.of(new com.example.takeout.model.SetmealOrder(500, 2)), "");

        assertEquals(20.0, order.goodsAmount(), 0.000001);
        assertEquals(20.0, jdbc.queryForObject("SELECT SUM(unit_price*quantity) FROM order_items WHERE order_id=?",
                java.math.BigDecimal.class, order.id()).doubleValue(), 0.000001);
        assertEquals(20.0, order.items().stream().mapToDouble(line -> line.price() * line.quantity()).sum(), 0.000001);
        assertEquals(994, count("SELECT stock FROM goods WHERE id=100"));
        adminService.orderFlow(order.id(), "cancel");
        assertEquals(1000, count("SELECT stock FROM goods WHERE id=100"));
    }

    @Test
    void paymentLedgerFailureRollsBackStateAndBalanceOnThreeArgumentPaymentEntry() {
        long id = service.createOrder(1, 10, List.of(item(102, 300)), 1, 0, "").id();
        doThrow(new DataAccessResourceFailureException("injected ledger failure"))
                .when(paymentRecords).insert(eq(id), anyLong(), anyDouble(), eq("PAY"), anyString(), anyString(), anyString());

        assertThrows(DataAccessResourceFailureException.class, () -> service.payOrder(1, id, "BALANCE", "QR", "135790"));

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

    @Test
    void confirmationAndRefundApplicationCannotBothWinTheEscrowRace() throws Exception {
        insertDeliveredOrder(900, 1, 0, 26);
        AtomicInteger confirmations = new AtomicInteger();
        AtomicInteger refunds = new AtomicInteger();

        runTogether(2, index -> {
            try {
                if (index == 0) {
                    service.confirmOrder(1, 900);
                    confirmations.incrementAndGet();
                } else {
                    service.applyRefund(1, 900, "OTHER", "concurrency test");
                    refunds.incrementAndGet();
                }
            } catch (BizException expectedRaceLoser) {
                // The losing transaction must not update escrow or create a refund.
            }
        });

        assertEquals(1, confirmations.get() + refunds.get());
        int status = count("SELECT status FROM orders WHERE id=900");
        int escrow = count("SELECT escrow_status FROM orders WHERE id=900");
        if (confirmations.get() == 1) {
            assertEquals(4, status);
            assertEquals(1, escrow);
            assertEquals(1020, count("SELECT balance FROM users WHERE id=99"));
            assertEquals(0, count("SELECT COUNT(*) FROM refund_records WHERE order_id=900"));
        } else {
            assertEquals(6, status);
            assertEquals(0, escrow);
            assertEquals(1000, count("SELECT balance FROM users WHERE id=99"));
            assertEquals(1, count("SELECT COUNT(*) FROM refund_records WHERE order_id=900"));
        }
    }

    @Test
    void concurrentRefundRetriesReturnOnePersistentApplicationAndProcessedReplay() throws Exception {
        insertDeliveredOrder(903, 1, 0, 1);
        var ids = java.util.concurrent.ConcurrentHashMap.<Long>newKeySet();
        runTogether(8, index -> ids.add(service.applyRefund(1, 903, "QUALITY_ISSUE", "汤洒了", "same-key").id()));
        assertEquals(1, ids.size());
        assertEquals(1, count("SELECT COUNT(*) FROM refund_records WHERE order_id=903"));
        assertEquals(1, count("SELECT COUNT(*) FROM refund_apply_requests WHERE order_id=903"));
        long firstId = ids.iterator().next();
        assertTrue(firstId > 0);
        assertEquals(firstId, new RefundDao(jdbc).findById(firstId).orElseThrow().id());

        adminService.rejectRefund(firstId, "  请补充具体情况  ");
        assertEquals("REJECTED", service.applyRefund(1, 903, "OTHER", "", "same-key").status());
        assertEquals(4, count("SELECT status FROM orders WHERE id=903"));
        assertEquals(1, count("SELECT COUNT(*) FROM refund_records WHERE order_id=903"));

        long nextId = service.applyRefund(1, 903, "OTHER", "补充：汤盒破损", "new-key").id();
        assertNotEquals(firstId, nextId);
        assertEquals(List.of(nextId, firstId), service.refundHistory(1, 903).stream()
                .map(com.example.takeout.model.RefundRecord::id).toList());
        assertEquals("请补充具体情况", service.refundHistory(1, 903).get(1).rejectReason());
        assertEquals(403, assertThrows(BizException.class, () -> service.refundHistory(2, 903)).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> service.applyRefund(2, 903, "OTHER", "餐损", "new-key")).getCode());
    }

    @Test
    void concurrentDistinctRefundIntentsReusePendingAndRefundedReplayNeverChangesMoneyOrStock() throws Exception {
        insertDeliveredOrder(904, 1, 0, 1);
        var ids = java.util.concurrent.ConcurrentHashMap.<Long>newKeySet();
        runTogether(8, index -> ids.add(service.applyRefund(1, 904, "OTHER", "餐损", "key-" + index).id()));
        assertEquals(1, ids.size());
        assertEquals(1, count("SELECT COUNT(*) FROM refund_records WHERE order_id=904"));
        assertEquals(8, count("SELECT COUNT(*) FROM refund_apply_requests WHERE order_id=904"));
        long id = ids.iterator().next();
        String winningKey = jdbc.queryForObject("SELECT request_key FROM refund_records WHERE id=?", String.class, id);
        adminService.approveRefund(id);
        assertEquals("REFUNDED", service.applyRefund(1, 904, null, null, winningKey).status());
        assertEquals(1023, count("SELECT balance FROM users WHERE id=1"));
        assertEquals(1000, count("SELECT stock FROM goods WHERE id=100"));
        assertEquals(1, count("SELECT COUNT(*) FROM payment_records WHERE order_id=904 AND type='REFUND'"));
        assertEquals(1, count("SELECT COUNT(*) FROM refund_records WHERE order_id=904"));
        for (int index = 0; index < 8; index++) {
            assertEquals(id, service.applyRefund(1, 904, null, null, "key-" + index).id());
        }
    }

    @Test
    void rejectedPendingAliasesReplayTheOriginalRefundAndNeverBecomeNewApplications() throws Exception {
        insertDeliveredOrder(907, 1, 0, 1);
        var ids = java.util.concurrent.ConcurrentHashMap.<Long>newKeySet();
        runTogether(8, index -> ids.add(service.applyRefund(1, 907, "OTHER", "餐损", "intent-" + index).id()));
        assertEquals(1, ids.size());
        long originalId = ids.iterator().next();
        assertEquals(8, count("SELECT COUNT(*) FROM refund_apply_requests WHERE order_id=907"));
        adminService.rejectRefund(originalId, "请补充说明");
        for (int index = 0; index < 8; index++) {
            var replay = service.applyRefund(1, 907, "OTHER", "", "intent-" + index);
            assertEquals(originalId, replay.id());
            assertEquals("REJECTED", replay.status());
        }
        assertEquals(1, count("SELECT COUNT(*) FROM refund_records WHERE order_id=907"));
        assertEquals(4, count("SELECT status FROM orders WHERE id=907"));
        long newId = service.applyRefund(1, 907, "OTHER", "新申请补充餐损情况", "intent-new").id();
        assertNotEquals(originalId, newId);
        assertEquals(originalId, service.applyRefund(1, 907, null, null, "intent-0").id());
        assertEquals(2, count("SELECT COUNT(*) FROM refund_records WHERE order_id=907"));
    }

    @Test
    void refundDaoReturnsGeneratedKeyOutsideATransactionAcrossIndependentConnections() {
        RefundDao dao = new RefundDao(jdbc);
        long first = dao.insert(905, 1, 99, "OTHER", "餐损", 13, "2026-10-26 12:00:00");
        long second = dao.insert(906, 2, 99, "OTHER", "餐损", 15, "2026-10-26 12:00:01", "key");
        assertTrue(first > 0);
        assertTrue(second > first);
        assertEquals(905, dao.findById(first).orElseThrow().orderId());
        assertEquals(906, dao.findById(second).orElseThrow().orderId());
        assertEquals(second, dao.findByRequestKey(906, "key").orElseThrow().id(),
                "主请求 key 应兼容未建立别名映射的存量申请");
    }

    @Test
    void autoConfirmCommitsEscrowMerchantNetAndOutboxExactlyOnce() {
        insertDeliveredOrder(901, 2, 0, 25);

        assertEquals(1, service.autoConfirmDeliveredOrders(24));
        assertEquals(1, count("SELECT escrow_status FROM orders WHERE id=901"));
        assertEquals(1020, count("SELECT balance FROM users WHERE id=99"));
        assertEquals(1, count("SELECT COUNT(*) FROM outbox_events WHERE order_id=901 AND event_type='ORDER_SETTLED'"));
        OrderDao.MerchantStatsAggregate stats = new OrderDao(jdbc).aggregateMerchantStats(10,
                "2000-01-01 00:00:00", "2099-01-01 00:00:00", "2000-01-01 00:00:00",
                "2000-01-01 00:00:00", List.of("2000-01-01 00:00:00", "2000-01-01 00:00:00",
                        "2000-01-01 00:00:00", "2000-01-01 00:00:00", "2000-01-01 00:00:00",
                        "2000-01-01 00:00:00", "2000-01-01 00:00:00"));
        assertEquals(20.0, stats.totalIncome(), 0.001);

        assertEquals(0, service.autoConfirmDeliveredOrders(24));
        assertEquals(1020, count("SELECT balance FROM users WHERE id=99"));
        assertEquals(1, count("SELECT COUNT(*) FROM outbox_events WHERE order_id=901 AND event_type='ORDER_SETTLED'"));
    }

    @Test
    void concurrentReviewsForSameOrderItemCreateOneRowAndAnonymousReadsAreRedacted() throws Exception {
        insertDeliveredOrder(902, 1, 1, 2,
                "[{\"goodsId\":100,\"goodsName\":\"goods100\",\"price\":10,\"quantity\":1,\"image\":\"\"}]");
        AtomicInteger successes = new AtomicInteger();
        runTogether(2, index -> {
            try {
                service.reviewOrder(1, 902, 100, 5, "good", List.of());
                successes.incrementAndGet();
            } catch (BizException duplicate) {
                assertEquals("该商品已评价", duplicate.getMessage());
            }
        });
        assertEquals(1, successes.get());
        assertEquals(1, count("SELECT COUNT(*) FROM reviews WHERE order_id=902 AND goods_id=100"));

        ReviewDao reviews = new ReviewDao(jdbc);
        reviews.insert(902, 10, 100, 1, "真实昵称", 5, "匿名", "[]", "[]", 1, "2026-10-18 00:00:00");
        UserCenterService center = new UserCenterService(null, null, null, reviews, new StoreDao(jdbc),
                new GoodsDao(jdbc, new GoodsSpecDao(jdbc)), null, new ObjectMapper(), null);
        Review.ReviewView anonymous = center.storeReviews(10).stream()
                .filter(view -> view.anonymous() == 1).findFirst().orElseThrow();
        assertEquals(0, anonymous.userId());
        assertEquals("", anonymous.userName());
    }

    private void insertDeliveredOrder(long id, long userId, int escrow, int hoursAgo) {
        insertDeliveredOrder(id, userId, escrow, hoursAgo, "[]");
    }

    private void insertDeliveredOrder(long id, long userId, int escrow, int hoursAgo, String items) {
        jdbc.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address," +
                        "goods_amount,delivery_fee,discount,pay_amount,reviewed,escrow_status,create_time," +
                        "pay_time,complete_time,create_time_dt,complete_time_dt) VALUES(?,?,?,10,'test',4,?," +
                        "'{}',20,3,0,23,0,?,NOW(),NOW(),DATE_FORMAT(DATE_SUB(NOW(),INTERVAL ? HOUR)," +
                        "'%Y-%m-%d %H:%i:%s'),NOW(),DATE_SUB(NOW(),INTERVAL ? HOUR))",
                id, "NO" + id, userId, items, escrow, hoursAgo, hoursAgo);
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
