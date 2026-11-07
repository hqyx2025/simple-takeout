package com.example.takeout.security;

import com.example.takeout.common.GlobalExceptionHandler;
import com.example.takeout.config.ClaimTrafficFilter;
import com.example.takeout.controller.UserCenterController;
import com.example.takeout.dao.*;
import com.example.takeout.service.UserCenterService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;
import org.springframework.transaction.support.TransactionTemplate;
import java.sql.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.atomic.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** 独立 MySQL 库 + HTTP 过滤器 + 真实发券事务；只对测试数据源注入连接故障。 */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class ClaimTrafficMySqlTest {
    private JdbcTemplate admin;
    private String schema;
    @AfterEach void clean() { if (admin != null && schema != null) admin.execute("DROP DATABASE `" + schema + "`"); }

    @Test void databaseOutageStopsBeforeAuthenticationAndRecoveryDoesNotIssueExtraCoupons() throws Exception {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1") + ":"
                + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv().getOrDefault("TAKEOUT_DB_PASSWORD", "");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        schema = "takeout_traffic_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + schema + "`");
        var source = new DriverManagerDataSource(base + schema + options, username, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        AtomicBoolean offline = new AtomicBoolean(); AtomicInteger connectionAttempts = new AtomicInteger();
        var gated = new DelegatingDataSource(source) {
            @Override public Connection getConnection() throws SQLException {
                connectionAttempts.incrementAndGet();
                if (offline.get()) throw new SQLTransientConnectionException("injected database outage", "08001");
                return super.getConnection();
            }
        };
        var db = new JdbcTemplate(gated);
        for (int id = 1; id <= 6; id++) db.update("INSERT INTO users(id,username,phone,password,create_time) VALUES(?,?,?,'test',NOW())",
                id, "user" + id, Long.toString(13800000000L + id));
        var stock = new CouponStockDao(db);
        var manager = new DataSourceTransactionManager(gated);
        new TransactionTemplate(manager).executeWithoutResult(status -> stock.initialize("满10减2", 10, 2));
        var target = new UserCenterService(new CouponDao(db), null, null, null, null, null, null,
                new ObjectMapper(), new UserCouponDao(db), null, null, stock);
        var proxy = new ProxyFactory(target);
        proxy.addAdvice(new TransactionInterceptor(manager, new AnnotationTransactionAttributeSource()));
        var center = (UserCenterService) proxy.getProxy();
        byte[] secret = new byte[32]; new java.security.SecureRandom().nextBytes(secret);
        var jwt = new JwtUtil(Base64.getEncoder().encodeToString(secret), 1);
        AtomicLong clock = new AtomicLong(1_000_000_000L);
        var guard = new ClaimTrafficGuard(mock(ObjectProvider.class), db, ClaimTrafficGuardTest.settings(4, 100, 1), clock::get);
        var mvc = MockMvcBuilders.standaloneSetup(new UserCenterController(center))
                .setControllerAdvice(new GlobalExceptionHandler())
                .addInterceptors(new AuthInterceptor(jwt, new UserDao(db), mock(TokenRevocationService.class)))
                .addFilters(new ClaimTrafficFilter(guard, jwt, new ObjectMapper())).build();
        String token = jwt.generateToken(1, 0);
        offline.set(true); int before = connectionAttempts.get();
        for (int i = 0; i < 32; i++) mvc.perform(post("/api/coupons/claim").header("Authorization", "Bearer " + token)
                .contentType("application/json").content("{\"storeId\":0,\"name\":\"\",\"threshold\":10,\"amount\":2}"))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value(503));
        assertEquals(1, connectionAttempts.get() - before, "熔断后不再查认证库，也不进入发券事务");
        offline.set(false); clock.addAndGet(Duration.ofSeconds(5).toNanos());
        for (int id = 1; id <= 5; id++) mvc.perform(post("/api/coupons/claim")
                .header("Authorization", "Bearer " + jwt.generateToken(id, 0)).contentType("application/json")
                .content("{\"storeId\":0,\"name\":\"\",\"threshold\":10,\"amount\":2}"))
                .andExpect(status().isOk());
        mvc.perform(post("/api/coupons/claim").header("Authorization", "Bearer " + jwt.generateToken(6, 0))
                .contentType("application/json").content("{\"storeId\":0,\"name\":\"\",\"threshold\":10,\"amount\":2}"))
                .andExpect(status().isConflict());
        assertEquals(5, db.queryForObject("SELECT COUNT(*) FROM coupons WHERE source='claim'", Integer.class));
        assertEquals(5, db.queryForObject("SELECT COUNT(*) FROM user_coupons", Integer.class));
    }
}
