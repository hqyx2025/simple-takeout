package com.example.takeout.service;

import com.example.takeout.dao.EmployeeDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.common.BizException;
import com.example.takeout.model.Goods;
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
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
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
    private GoodsDao goods;
    private TransactionTemplate transaction;

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
        jdbc.update("INSERT INTO stores(review_status,id,name,owner_id,create_time) VALUES(1,10,'test',99,'2026-01-01 00:00:00')");
        jdbc.update("INSERT INTO categories(id,name,type) VALUES(1,'test','PLATFORM')");

        cache = mock(HotDataCacheService.class);
        specs = spy(new GoodsSpecDao(jdbc));
        goods = new GoodsDao(jdbc, specs);
        transaction = new TransactionTemplate(new DataSourceTransactionManager(source));
        var target = new StoreService(new StoreDao(jdbc), goods, specs,
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
    void storeGalleryPersistsTwentyPhotosAndRejectsTwentyOneWithoutChangingTheCover() {
        var photos = java.util.stream.IntStream.range(0, 20).mapToObj(i -> "/uploads/photo-" + i + ".png").toList();
        var created = service.createStore(99, "相册店铺", 1, 3, 20, "30分钟", "", "测试地址",
                30.5, 114.3, 10000, "", photos);
        var reloaded = new StoreDao(jdbc).findById(created.id()).orElseThrow();
        assertEquals(photos, reloaded.images()); assertEquals(photos.getFirst(), reloaded.image());
        assertEquals(photos, reloaded.withDistance(30.5, 114.3).images());
        var tooMany = java.util.Collections.nCopies(21, photos.getFirst());
        assertThrows(com.example.takeout.common.BizException.class, () -> service.createStore(99, "过多照片", 1,
                3, 20, "30分钟", "", "测试地址", 30.5, 114.3, 10000, "", tooMany));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM stores WHERE name='过多照片'", Integer.class));
    }

    @Test
    void galleryMigrationUpgradesLegacyStoresAndCanRunAgainWithoutLosingTheirCover() {
        jdbc.update("UPDATE stores SET image='/uploads/legacy.jpg' WHERE id=10");
        jdbc.execute("ALTER TABLE stores DROP COLUMN images");
        var migration = new ResourceDatabasePopulator(new ClassPathResource("db/migration/app/V5__store_photo_gallery.sql"));
        migration.execute(jdbc.getDataSource()); migration.execute(jdbc.getDataSource());
        assertEquals(List.of("/uploads/legacy.jpg"), new StoreDao(jdbc).findById(10).orElseThrow().images());
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

    @Test
    void staleGoodsFormCannotRestoreSoldInventory() throws Exception {
        Goods created = service.addGoods(99, 10, singleGoodsInput("original", 5));
        var locked = new CountDownLatch(1);
        var release = new CountDownLatch(1);
        var editStarted = new CountDownLatch(1);
        try (var workers = Executors.newFixedThreadPool(2)) {
            var sale = workers.submit(() -> transaction.executeWithoutResult(status -> {
                goods.lockStockRows(List.of(created.id()));
                assertTrue(goods.deductStock(created.id(), 1));
                locked.countDown();
                await(release);
            }));
            assertTrue(locked.await(10, TimeUnit.SECONDS));
            var edit = workers.submit(() -> {
                editStarted.countDown();
                return service.updateGoods(99, created.id(), singleGoodsInput("renamed", 5));
            });
            try { assertTrue(editStarted.await(10, TimeUnit.SECONDS)); }
            finally { release.countDown(); }
            sale.get(10, TimeUnit.SECONDS);
            edit.get(10, TimeUnit.SECONDS);
        } finally { release.countDown(); }
        Goods result = goods.findById(created.id()).orElseThrow();
        assertEquals("renamed", result.name());
        assertEquals(4, result.stock(), "editing metadata must not revive the sold unit");
        assertEquals(1, result.version());
    }

    @Test
    void staleSpecFormPreservesBothSkuAndAggregateInventory() {
        Goods created = service.addGoods(99, 10, goodsInput());
        long specId = created.specs().getFirst().id();
        transaction.executeWithoutResult(status -> {
            goods.lockStockRows(List.of(created.id()));
            assertTrue(specs.deductStock(specId, 2));
            assertTrue(goods.deductStock(created.id(), 2));
        });
        Goods result = service.updateSpecs(99, created.id(),
                List.of(new StoreService.SpecInput(specId, "large renamed", 12, 5)));
        assertEquals(3, result.stock());
        assertEquals(3, result.specs().getFirst().stock());
        assertEquals("large renamed", result.specs().getFirst().name());
        assertEquals(12, result.price());
    }

    @Test
    void competingCountsUseTheVersionAndOnlyOneCanCommit() throws Exception {
        Goods created = service.addGoods(99, 10, singleGoodsInput("counted", 5));
        var start = new CountDownLatch(1);
        try (var workers = Executors.newFixedThreadPool(2)) {
            var first = workers.submit(() -> countAttempt(created, 10, start));
            var second = workers.submit(() -> countAttempt(created, 20, start));
            start.countDown();
            List<Integer> codes = List.of(first.get(10, TimeUnit.SECONDS), second.get(10, TimeUnit.SECONDS));
            assertEquals(1, codes.stream().filter(code -> code == 200).count());
            assertEquals(1, codes.stream().filter(code -> code == 409).count());
        }
        Goods result = goods.findById(created.id()).orElseThrow();
        assertTrue(result.stock() == 10 || result.stock() == 20);
        assertEquals(1, result.version());
    }

    @Test
    void replenishmentIsAdditiveAndRetryCannotAddItTwice() {
        Goods created = service.addGoods(99, 10, goodsInput());
        var spec = created.specs().getFirst();
        Goods result = service.replenishStock(99, created.id(), spec.id(), 7, spec.version());
        assertEquals(12, result.stock());
        assertEquals(12, result.specs().getFirst().stock());
        assertEquals(spec.version() + 1, result.specs().getFirst().version());
        assertEquals(409, assertThrows(BizException.class,
                () -> service.replenishStock(99, created.id(), spec.id(), 7, spec.version())).getCode());
        assertEquals(12, goods.findById(created.id()).orElseThrow().stock());
    }

    @Test
    void returnedInventoryInvalidatesAStaleCountAndUnavailableSpecKeepsItsHistory() {
        Goods created = service.addGoods(99, 10, goodsInput());
        var spec = created.specs().getFirst();
        transaction.executeWithoutResult(status -> {
            goods.lockStockRows(List.of(created.id()));
            specs.restoreStock(spec.id(), 2);
            goods.restoreStock(created.id(), 2);
        });
        assertEquals(409, assertThrows(BizException.class,
                () -> service.updateStock(99, created.id(), spec.id(), 0, spec.version())).getCode());
        service.updateSpecs(99, created.id(), List.of());
        assertEquals(7, specs.findById(spec.id()).orElseThrow().stock());
        assertEquals(0, specs.findById(spec.id()).orElseThrow().status());
    }

    @Test
    void stockChangesRejectMissingVersionWrongOwnerAndForeignSpecWithoutWrites() {
        Goods created = service.addGoods(99, 10, singleGoodsInput("protected", 5));
        assertEquals(409, assertThrows(BizException.class,
                () -> service.updateStock(99, created.id(), 0, 0, null)).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> service.updateStock(98, created.id(), 0, 0, created.version())).getCode());
        assertEquals(409, assertThrows(BizException.class,
                () -> service.replenishStock(99, created.id(), 9999, 2, created.version())).getCode());
        assertEquals(5, goods.findById(created.id()).orElseThrow().stock());
        assertEquals(created.version(), goods.findById(created.id()).orElseThrow().version());
    }

    private int countAttempt(Goods created, int stock, CountDownLatch start) {
        await(start);
        try {
            service.updateStock(99, created.id(), 0, stock, created.version());
            return 200;
        } catch (BizException failure) {
            return failure.getCode();
        }
    }

    private static void await(CountDownLatch latch) {
        try { assertTrue(latch.await(10, TimeUnit.SECONDS)); }
        catch (InterruptedException failure) { Thread.currentThread().interrupt(); throw new AssertionError(failure); }
    }

    private StoreService.GoodsInput singleGoodsInput(String name, int stock) {
        return new StoreService.GoodsInput(name, "", 10, 0, "", 1, "", 1, 0, stock, false, null);
    }

    private StoreService.GoodsInput goodsInput() {
        return new StoreService.GoodsInput("test goods", "", 10, 0, "", 1, "", 1,
                0, 0, false, List.of(new StoreService.SpecInput(0, "large", 10, 5)));
    }

    private int count(String sql) {
        return jdbc.queryForObject(sql, Integer.class);
    }
}
