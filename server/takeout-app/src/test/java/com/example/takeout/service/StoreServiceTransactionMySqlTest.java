package com.example.takeout.service;

import com.example.takeout.dao.EmployeeDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.core.io.ClassPathResource;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;

import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.verify;

/** Opt-in MySQL regression for atomic goods/SKU updates and commit-aware cache eviction. */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class StoreServiceTransactionMySqlTest {

    private JdbcTemplate admin;
    private JdbcTemplate jdbc;
    private String database;
    private HotDataCacheService cache;
    private GoodsSpecDao specs;
    private StoreService service;

    @BeforeEach
    void setUp() {
        String host = System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1");
        String port = System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310");
        String base = "jdbc:mysql://" + host + ":" + port + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, username, password));
        database = "takeout_store_tx_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + database + "`");
        var source = new DriverManagerDataSource(base + database + options, username, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        jdbc.update("INSERT INTO stores(id,name,owner_id,create_time) VALUES(10,'test',99,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO categories(id,name,type) VALUES(1,'test','PLATFORM')");

        cache = mock(HotDataCacheService.class);
        specs = spy(new GoodsSpecDao(jdbc));
        var target = new StoreService(new StoreDao(jdbc), new GoodsDao(jdbc, specs), specs,
                mock(SeckillDao.class), new ObjectMapper(), cache, mock(EmployeeDao.class));
        var proxy = new ProxyFactory(target);
        proxy.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(source),
                new AnnotationTransactionAttributeSource()));
        service = (StoreService) proxy.getProxy();
    }

    @AfterEach
    void cleanUp() {
        if (database != null) {
            admin.execute("DROP DATABASE `" + database + "`");
        }
    }

    @Test
    void skuFailureRollsBackGoodsAndDoesNotEvictCache() {
        doThrow(new DataAccessResourceFailureException("injected SKU failure"))
                .when(specs).insert(anyLong(), anyString(), anyDouble(), anyInt(), anyInt());

        assertThrows(DataAccessResourceFailureException.class, () -> service.addGoods(99, 10, goodsInput()));

        assertEquals(0, count("SELECT COUNT(*) FROM goods"));
        assertEquals(0, count("SELECT COUNT(*) FROM goods_specs"));
        verify(cache, never()).evictByPattern(anyString());
    }

    @Test
    void successfulSkuUpdateEvictsCacheAfterCommit() {
        service.addGoods(99, 10, goodsInput());

        assertEquals(1, count("SELECT COUNT(*) FROM goods"));
        assertEquals(1, count("SELECT COUNT(*) FROM goods_specs"));
        verify(cache, atLeastOnce()).evictByPattern(anyString());
    }

    private StoreService.GoodsInput goodsInput() {
        return new StoreService.GoodsInput("test goods", "", 10, 0, "", 1, "", 1,
                0, 0, false, List.of(new StoreService.SpecInput(0, "large", 10, 5)));
    }

    private int count(String sql) {
        return jdbc.queryForObject(sql, Integer.class);
    }
}
