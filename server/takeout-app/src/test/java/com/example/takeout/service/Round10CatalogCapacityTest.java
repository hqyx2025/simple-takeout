package com.example.takeout.service;

import com.example.takeout.model.Store;
import com.fasterxml.jackson.core.type.TypeReference;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.data.redis.core.StringRedisTemplate;
import java.nio.charset.StandardCharsets;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round10CatalogCapacityTest {
    static List<Store> catalog(int size) {
        var result = new ArrayList<Store>();
        for (int i=1;i<=size;i++) result.add(new Store(i,"示例川菜馆（第"+i+"分店）","/uploads/20261025/abcdef"+i+".jpg",
                4.6,1234,3,20,"30分钟","1.2km","[\"川菜\",\"快餐\"]","本店招牌菜麻辣香锅，欢迎光临",
                "湖北省武汉市洪山区珞喻路"+(100+i)+"号",30.5,114.3,3,"[3,7]",2,1,1,"2026-10-25 12:00:00",3000));
        return result;
    }

    @Test void fiveHundredStoreCatalogActuallyFillsAndSecondLocationHits() {
        var f = new Round9CacheEfficiencyTest.Fixture(); f.rows.clear();f.rows.addAll(catalog(500));
        assertEquals(500,f.service.listStores(null,30.5,114.3).size());
        assertEquals(500,f.service.listStores(null,30.6,114.4).size());
        long bytes=f.values.values().stream().mapToLong(value->value.getBytes(StandardCharsets.UTF_8).length).sum();
        System.out.println("[RT-38/catalog] stores=500 source-loads="+f.storeLoads.get()+" value-keys="+f.values.size()+" encoded-bytes="+bytes);
        assertEquals(1,f.storeLoads.get()); assertEquals(1,f.values.size()); assertTrue(bytes>65536 && bytes<=1048576);
    }

    @Test void configuredCapacityBindsAndInvalidValuesFailStartup() {
        var runner=new ApplicationContextRunner().withBean(StringRedisTemplate.class,()->mock(StringRedisTemplate.class))
                .withBean(com.fasterxml.jackson.databind.ObjectMapper.class,com.fasterxml.jackson.databind.ObjectMapper::new)
                .withUserConfiguration(HotDataCacheService.class);
        for(String invalid:List.of("65535","4194305")) runner.withPropertyValues("takeout.cache.max-entry-bytes="+invalid)
                .run(ctx->assertNotNull(ctx.getStartupFailure()));
        runner.withPropertyValues("takeout.cache.max-entry-bytes=2097152").run(ctx->{
            assertNull(ctx.getStartupFailure());
            assertEquals(2097152L,org.springframework.test.util.ReflectionTestUtils.getField(ctx.getBean(HotDataCacheService.class),"maxEntryBytes"));
        });
        System.out.println("[RT-38/config] 2MiB property bound; below-64KiB/above-4MiB rejected");
    }

    @Test void oversizeIsVisibleAtInfoAndWarningsAreBoundedWhileDynamicCapIsRetained() {
        var f=new Round9CacheEfficiencyTest.Fixture();
        var logger=(ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(HotDataCacheService.class);
        var previous=logger.getLevel();logger.setLevel(ch.qos.logback.classic.Level.INFO);
        var entries=new ch.qos.logback.core.read.ListAppender<ch.qos.logback.classic.spi.ILoggingEvent>();entries.start();logger.addAppender(entries);
        try {
            var large="x".repeat(1100000);
            for(int i=0;i<3;i++) assertEquals(large,f.cache.get(HotDataCacheService.Keys.ALL_STORES,new TypeReference<String>(){},()->large));
            var warnings=entries.list.stream().filter(e->e.getLevel()==ch.qos.logback.classic.Level.WARN).toList();
            System.out.println("[RT-38/warn] repeated-oversize=3 WARN="+warnings.size()+" cached-values="+f.values.size());
            assertEquals(1,warnings.size());String message=warnings.getFirst().getFormattedMessage();
            assertTrue(message.contains(HotDataCacheService.Keys.ALL_STORES));assertTrue(message.contains("bytes="));assertTrue(message.contains("limit=1048576"));
            assertTrue(f.values.isEmpty());
            String dynamic="x".repeat(70000);f.cache.get("dynamic:store",new TypeReference<String>(){},()->dynamic);
            assertTrue(f.values.isEmpty());
        } finally {logger.detachAppender(entries);entries.stop();logger.setLevel(previous);}
    }
}
