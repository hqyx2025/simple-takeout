package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.UserDao;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
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

import java.util.ArrayList;
import java.util.List;
import java.util.Queue;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Opt-in MySQL regression for per-user address serialization. */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class UserCenterAddressConcurrencyMySqlTest {

    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private String database;
    private UserCenterService service;

    @BeforeEach
    void setUp() {
        String host = System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1");
        String port = System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310");
        String base = "jdbc:mysql://" + host + ":" + port + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        database = "takeout_address_concurrency_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");

        var source = new DriverManagerDataSource(base + database + options, username, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        jdbc.update("INSERT INTO users(id,username,phone,password,create_time) " +
                "VALUES(1,'address-user','13800138000','test','2026-01-01 00:00:00')");

        var target = new UserCenterService(null, null, new AddressDao(jdbc), null, null, null,
                null, new ObjectMapper(), null, new UserDao(jdbc), null);
        var proxy = new ProxyFactory(target);
        proxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(source),
                new AnnotationTransactionAttributeSource()));
        service = (UserCenterService) proxy.getProxy();
    }

    @AfterEach
    void cleanUp() {
        if (admin != null && database != null) {
            admin.execute("DROP DATABASE IF EXISTS `" + database + "`");
        }
    }

    @Test
    void concurrentAddsCannotExceedTwentyAddresses() throws Exception {
        for (int i = 1; i <= 19; i++) {
            insertAddress(i, i == 1 ? 1 : 0);
        }
        AtomicInteger successes = new AtomicInteger();

        runTogether(8, index -> {
            try {
                service.addAddress(1, "联系人" + index, "13800138000", "并发地址" + index, 0);
                successes.incrementAndGet();
            } catch (BizException full) {
                assertEquals("收货地址最多保存 20 个，请先删除部分地址", full.getMessage());
            }
        });

        assertEquals(1, successes.get());
        assertEquals(20, count("SELECT COUNT(*) FROM addresses WHERE user_id=1"));
    }

    @Test
    void concurrentRetriesOfSameAddressReturnOneRow() throws Exception {
        Queue<Long> ids = new ConcurrentLinkedQueue<>();

        runTogether(8, index -> ids.add(service.addAddress(1, " 张女士 ", " 13800138000 ", "ignored", 1,
                22.81670004, 108.32000004, " 南宁学院东门 ", " 3栋1206 ", "学校").id()));

        assertEquals(8, ids.size());
        assertEquals(1, ids.stream().distinct().count());
        assertEquals(1, count("SELECT COUNT(*) FROM addresses WHERE user_id=1"));
        assertEquals("学校", jdbc.queryForObject("SELECT tag FROM addresses WHERE user_id=1", String.class));
    }

    @Test
    void concurrentDefaultSwitchesLeaveExactlyOneDefault() throws Exception {
        for (int i = 1; i <= 8; i++) {
            insertAddress(i, i == 1 ? 1 : 0);
        }
        List<Long> ids = jdbc.queryForList("SELECT id FROM addresses ORDER BY id", Long.class);

        runTogether(ids.size(), index -> service.setDefaultAddress(1, ids.get(index)));

        assertEquals(1, count("SELECT COUNT(*) FROM addresses WHERE user_id=1 AND is_default=1"));
    }

    @Test
    void invalidDefaultTargetCannotClearCurrentDefault() {
        insertAddress(1, 1);

        assertThrows(BizException.class, () -> service.setDefaultAddress(1, 9999));

        assertEquals(1, count("SELECT COUNT(*) FROM addresses WHERE user_id=1 AND is_default=1"));
    }

    private void insertAddress(int suffix, int isDefault) {
        jdbc.update("INSERT INTO addresses(user_id,name,phone,detail,is_default,create_time) " +
                        "VALUES(1,?,'13800138000',?,?, '2026-01-01 00:00:00')",
                "联系人" + suffix, "地址" + suffix, isDefault);
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
            for (Future<?> future : futures) {
                future.get(30, TimeUnit.SECONDS);
            }
        }
    }

    private interface Work {
        void run(int index) throws Exception;
    }
}
