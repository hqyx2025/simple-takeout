package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.example.takeout.model.User;
import com.example.takeout.security.*;
import com.example.takeout.service.thirdparty.SmsSender;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.mock.web.*;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;

import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** Real isolated MySQL + Redis; only email/SMS transport is replaced by a capturing sender. */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class AccountBoundaryMySqlTest {
    private static final String PASSWORD = "Account-test-47!";
    private static final String NOW = "2026-11-12 12:00:00";
    private JdbcTemplate admin, db;
    private String schema;
    private DataSourceTransactionManager transactionManager;
    private LettuceConnectionFactory redisFactory;
    private UserDao users;
    private JwtUtil jwt;
    private RefreshTokenService refresh;
    private ContactVerificationService contacts;
    private AccountClosureService closure;
    private AuthService auth;
    private AuthInterceptor interceptor;
    private PersonalDataCrypto crypto;
    private User customer;
    private String sentCode;
    private int deliveries;

    @BeforeEach void start() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1") + ":"
                + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root"), password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        schema = "takeout_account_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + schema + "`");
        var source = new DriverManagerDataSource(base + schema + options, username, password);
        db = new JdbcTemplate(source); transactionManager = new DataSourceTransactionManager(source);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        Flyway.configure().dataSource(source).locations("classpath:db/migration/app")
                .baselineOnMigrate(true).baselineVersion("0").load().migrate();
        crypto = new PersonalDataCrypto(key(), key(), "", new ObjectMapper());
        users = transactional(new UserDao(db, crypto));
        jwt = new JwtUtil(key(), 1);
        var blacklist = new TokenBlacklistDao(db);
        refresh = transactional(new RefreshTokenService(blacklist, users, jwt));
        interceptor = new AuthInterceptor(jwt, users, new TokenRevocationService(jwt, blacklist));
        redisFactory = new LettuceConnectionFactory("127.0.0.1", Integer.parseInt(System.getenv().getOrDefault("TAKEOUT_TEST_REDIS_PORT", "6387")));
        redisFactory.afterPropertiesSet();
        var redis = new StringRedisTemplate(redisFactory); redis.afterPropertiesSet();
        try (var connection = redis.getConnectionFactory().getConnection()) { assertEquals("PONG", connection.ping()); }
        SmsSender sender = new SmsSender() {
            @Override public void sendSmsCode(String destination, String code) { sentCode = code; deliveries++; }
        };
        var codes = new SmsVerificationService(redis, sender, UUID.randomUUID().toString(), 900, 1, 0, 0);
        contacts = transactional(new ContactVerificationService(users, db, codes, crypto, new MockEnvironment(), new ObjectMapper()));
        var authTarget = new AuthService(users, jwt, codes);
        ReflectionTestUtils.setField(authTarget, "contactVerification", contacts);
        auth = transactional(authTarget);
        closure = transactional(new AccountClosureService(users, db, crypto));
        customer = users.insert("account-owner", "13800138000", randomEmail(), PasswordUtil.hash(PASSWORD), 0, 0, NOW);
    }

    @AfterEach void stop() {
        if (redisFactory != null) redisFactory.destroy();
        if (schema != null) admin.execute("DROP DATABASE `" + schema + "`");
    }

    @SuppressWarnings("unchecked") private <T> T transactional(T target) {
        var proxy = new ProxyFactory(target); proxy.setProxyTargetClass(true);
        proxy.addAdvice(new TransactionInterceptor(transactionManager, new AnnotationTransactionAttributeSource()));
        return (T) proxy.getProxy();
    }
    private String key() { byte[] bytes = new byte[32]; new java.security.SecureRandom().nextBytes(bytes); return Base64.getEncoder().encodeToString(bytes); }
    private String randomEmail() { return UUID.randomUUID().toString() + "@example.test"; }
    private boolean accepts(String token) {
        var request = new MockHttpServletRequest("GET", "/api/auth/me");
        request.addHeader("Authorization", "Bearer " + token);
        return interceptor.preHandle(request, new MockHttpServletResponse(), new Object());
    }
    private String access(User user) { return jwt.generateToken(user.id(), user.role(), user.passwordChangedAt()); }

    @Test void disablingAndReenablingNeverRevivesOldAccessOrRefreshCredentials() {
        for (int role : List.of(0, 1)) {
            User user = role == 0 ? customer : users.insert("employee", "13800138001", randomEmail(), PasswordUtil.hash(PASSWORD), 1, 0, NOW);
            String oldAccess = access(user), oldRefresh = refresh.issue(user.id(), oldAccess);
            assertTrue(accepts(oldAccess));
            if (role == 0) { users.updateStatus(user.id(), 0); users.updateStatus(user.id(), 1); }
            else { users.updateEmployeeStatus(user.id(), 0); users.updateEmployeeStatus(user.id(), 1); }
            assertEquals(401, assertThrows(BizException.class, () -> accepts(oldAccess)).getCode());
            assertEquals(401, assertThrows(BizException.class, () -> refresh.refresh(oldRefresh)).getCode());
            assertTrue(accepts(access(users.findById(user.id()).orElseThrow())));
        }
    }

    @Test void contactProofIsBoundToAccountKindDestinationAndCredentialVersionAndConsumedOnce() {
        var other = users.insert("other", "13800138001", randomEmail(), PasswordUtil.hash(PASSWORD), 0, 0, NOW);
        String target = randomEmail();
        contacts.send(customer.id(), "EMAIL", target.toUpperCase(Locale.ROOT), PASSWORD);
        String code = sentCode; assertEquals(1, deliveries);
        assertThrows(BizException.class, () -> contacts.verify(other, "EMAIL", target, code));
        assertThrows(BizException.class, () -> contacts.verify(customer, "PHONE", "13800138001", code));
        assertThrows(BizException.class, () -> contacts.verify(customer, "EMAIL", randomEmail(), code));
        String wrongCode = "000000".equals(code) ? "111111" : "000000";
        assertThrows(BizException.class, () -> auth.updateProfile(customer.id(), "owner", customer.phone(), target, PASSWORD, "", wrongCode));
        assertEquals(customer.email(), users.findById(customer.id()).orElseThrow().email());
        String oldAccess = access(customer);
        var updated = auth.updateProfile(customer.id(), "owner", customer.phone(), target, PASSWORD, "", code);
        assertEquals(target, updated.email()); assertTrue(contacts.status(customer.id()).emailVerified());
        assertFalse(contacts.status(customer.id()).phoneVerified());
        assertEquals(401, assertThrows(BizException.class, () -> accepts(oldAccess)).getCode());
        assertThrows(BizException.class, () -> contacts.verify(customer, "EMAIL", target, code), "the consumed old proof cannot be replayed");
        String pendingTarget = randomEmail();
        contacts.send(customer.id(), "EMAIL", pendingTarget, PASSWORD);
        String beforeReset = sentCode;
        auth.changePassword(customer.id(), PASSWORD, "Changed-password-48!");
        assertThrows(BizException.class, () -> contacts.verify(users.findById(customer.id()).orElseThrow(), "EMAIL", pendingTarget, beforeReset));
    }

    @Test void currentContactCanBeVerifiedWithoutEndingSessionAndUnavailableSmsCannotSend() {
        String token = access(customer);
        contacts.send(customer.id(), "EMAIL", customer.email(), PASSWORD);
        contacts.verifyCurrent(customer.id(), "EMAIL", customer.email(), PASSWORD, sentCode);
        assertTrue(contacts.status(customer.id()).emailVerified()); assertTrue(accepts(token));
        assertFalse(contacts.status(customer.id()).phoneAvailable());
        assertEquals(503, assertThrows(BizException.class, () -> contacts.send(customer.id(), "PHONE", customer.phone(), PASSWORD)).getCode());
        assertThrows(BizException.class, () -> contacts.send(customer.id(), "EMAIL", randomEmail(), "wrong"));
        assertEquals(1, deliveries);
        assertEquals("renamed", auth.updateProfile(customer.id(), "renamed", customer.phone(), customer.email(), "").username());
    }

    private long order(int status, int escrow) {
        db.update("INSERT INTO orders(order_no,user_id,store_id,store_name,status,items,address,pay_amount,escrow_status,create_time) " +
                        "VALUES(?,?,1,'test-store',?,'[]',?,20,?,?)", UUID.randomUUID().toString().replace("-", ""), customer.id(), status,
                crypto.encrypt("{\"addressId\":1,\"name\":\"Private Name\",\"phone\":\"13800138000\",\"detail\":\"Private Door\"}", "orders.address"), escrow, NOW);
        return db.queryForObject("SELECT MAX(id) FROM orders WHERE user_id=?", Long.class, customer.id());
    }
    private void stillOpen() {
        assertEquals(1, users.findById(customer.id()).orElseThrow().status());
        assertEquals(customer.phone(), users.findById(customer.id()).orElseThrow().phone());
    }

    @Test void closureRejectsUnsettledBalancesOrdersPaymentsRefundsAndWrongPasswordsWithoutDeletingData() {
        assertThrows(BizException.class, () -> closure.close(customer.id(), "wrong")); stillOpen();
        db.update("UPDATE users SET balance=0.01 WHERE id=?", customer.id());
        assertThrows(BizException.class, () -> closure.close(customer.id(), PASSWORD)); stillOpen();
        db.update("UPDATE users SET balance=0 WHERE id=?", customer.id());
        for (int status : List.of(0, 1, 2, 3, 4, 6)) {
            long id = order(status, 0);
            assertThrows(BizException.class, () -> closure.close(customer.id(), PASSWORD), "active status " + status);
            stillOpen(); db.update("DELETE FROM orders WHERE id=?", id);
        }
        long inconsistentCancellation = order(5, 1);
        assertThrows(BizException.class, () -> closure.close(customer.id(), PASSWORD)); stillOpen();
        db.update("UPDATE orders SET escrow_status=0,pay_time=? WHERE id=?", NOW, inconsistentCancellation);
        assertThrows(BizException.class, () -> closure.close(customer.id(), PASSWORD)); stillOpen();
        db.update("DELETE FROM orders WHERE id=?", inconsistentCancellation);
        long id = order(4, 1);
        db.update("INSERT INTO payment_transactions(order_id,user_id,channel,amount,out_trade_no,status,create_time) VALUES(?,?,'ALIPAY',20,'pending-account-payment','PENDING',?)", id, customer.id(), NOW);
        assertThrows(BizException.class, () -> closure.close(customer.id(), PASSWORD)); stillOpen();
        db.update("DELETE FROM payment_transactions WHERE order_id=?", id);
        db.update("INSERT INTO refund_records(order_id,user_id,merchant_id,amount,status,apply_time) VALUES(?,?,2,1,'PENDING',?)", id, customer.id(), NOW);
        assertThrows(BizException.class, () -> closure.close(customer.id(), PASSWORD)); stillOpen();
    }

    @Test void closureRemovesPrivateDataButPreservesOrdersMoneyAndPermanentRevocation() {
        long order = order(4, 1);
        db.update("INSERT INTO payment_records(order_id,user_id,amount,type,channel,status,create_time) VALUES(?,?,20,'PAY','ALIPAY','SUCCESS',?)", order, customer.id(), NOW);
        db.update("UPDATE users SET balance=1 WHERE id=?", customer.id()); db.update("UPDATE users SET balance=0 WHERE id=?", customer.id());
        long movements = db.queryForObject("SELECT COUNT(*) FROM wallet_movements WHERE user_id=?", Long.class, customer.id());
        new AddressDao(db, crypto).insert(customer.id(), "Private Name", customer.phone(), "Private Door", 1, null, null, null, null, "", NOW);
        db.update("INSERT INTO bank_cards(user_id,bank_name,card_type,card_no_last4,create_time) VALUES(?,'test','test','1234',?)", customer.id(), NOW);
        new PushTokenDao(db).register(customer.id(), "test-device-hash", "encrypted-test-device", 1);
        String oldAccess = access(customer), oldRefresh = refresh.issue(customer.id(), oldAccess);
        closure.close(customer.id(), PASSWORD);
        var closed = users.findById(customer.id()).orElseThrow();
        assertEquals(0, closed.status()); assertEquals("!" + customer.id(), closed.phone()); assertNull(closed.email()); assertEquals("", closed.password());
        for (String table : List.of("addresses", "bank_cards", "push_tokens", "user_phone_search"))
            assertEquals(0, db.queryForObject("SELECT COUNT(*) FROM " + table + " WHERE user_id=?", Integer.class, customer.id()), table);
        assertEquals(1, db.queryForObject("SELECT COUNT(*) FROM orders WHERE id=? AND pay_amount=20 AND status=4 AND escrow_status=1", Integer.class, order));
        assertEquals(1, db.queryForObject("SELECT COUNT(*) FROM payment_records WHERE order_id=? AND amount=20", Integer.class, order));
        assertEquals(movements, db.queryForObject("SELECT COUNT(*) FROM wallet_movements WHERE user_id=?", Long.class, customer.id()));
        String address = crypto.decrypt(db.queryForObject("SELECT address FROM orders WHERE id=?", String.class, order), "orders.address");
        assertFalse(address.contains("Private")); assertFalse(address.contains(customer.phone()));
        assertEquals(401, assertThrows(BizException.class, () -> accepts(oldAccess)).getCode());
        assertThrows(BizException.class, () -> refresh.refresh(oldRefresh));
        assertThrows(BizException.class, () -> users.updateStatus(customer.id(), 1));
        assertThrows(BizException.class, () -> auth.updateProfile(customer.id(), "resurrected", "13800138002", "new@example.test", PASSWORD));
        assertFalse(users.updateAvatar(customer.id(), "/uploads/old-request.jpg"));
    }

    @Test void closureAndNewObligationSerializeAcrossIndependentConnections() throws Exception {
        var holding = new CountDownLatch(1); var release = new CountDownLatch(1);
        var transaction = new org.springframework.transaction.support.TransactionTemplate(transactionManager);
        try (var pool = Executors.newFixedThreadPool(2)) {
            Future<?> creating = pool.submit(() -> transaction.executeWithoutResult(status -> {
                users.lockActiveCustomerLifecycle(customer.id()); holding.countDown();
                try { assertTrue(release.await(5, TimeUnit.SECONDS)); } catch (InterruptedException e) { throw new RuntimeException(e); }
                order(0, 0);
            }));
            assertTrue(holding.await(5, TimeUnit.SECONDS));
            var closingStarted = new CountDownLatch(1);
            Future<Boolean> closing = pool.submit(() -> {
                closingStarted.countDown();
                try { closure.close(customer.id(), PASSWORD); return true; }
                catch (BizException expected) { return false; }
            });
            assertTrue(closingStarted.await(5, TimeUnit.SECONDS));
            assertThrows(TimeoutException.class, () -> closing.get(100, TimeUnit.MILLISECONDS), "closure must wait for the in-flight obligation");
            release.countDown(); creating.get(10, TimeUnit.SECONDS); assertFalse(closing.get(10, TimeUnit.SECONDS));
            stillOpen(); assertEquals(1, db.queryForObject("SELECT COUNT(*) FROM orders WHERE user_id=? AND status=0", Integer.class, customer.id()));
        } finally { release.countDown(); }
        db.update("DELETE FROM orders WHERE user_id=?", customer.id()); closure.close(customer.id(), PASSWORD);
        assertThrows(BizException.class, () -> transaction.executeWithoutResult(status -> users.lockActiveCustomerLifecycle(customer.id())));
    }
}
