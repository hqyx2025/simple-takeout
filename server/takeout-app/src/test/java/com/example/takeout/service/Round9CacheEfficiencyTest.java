package com.example.takeout.service;

import com.example.takeout.dao.*;
import com.example.takeout.model.Store;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.*;
import org.springframework.data.redis.core.script.RedisScript;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round9CacheEfficiencyTest {
    private static final TypeReference<String> TEXT = new TypeReference<>() {};
    static class Fixture {
        final Map<String,String> values = new ConcurrentHashMap<>();
        final CountDownLatch contended = new CountDownLatch(1);
        final HotDataCacheService cache;
        final StoreDao stores = mock(StoreDao.class);
        final GoodsDao goods = mock(GoodsDao.class);
        final SeckillDao seckills = mock(SeckillDao.class);
        final StoreService service;
        final AtomicInteger storeLoads = new AtomicInteger();
        final List<Store> rows = new ArrayList<>();
        Fixture() {
            var redis = mock(StringRedisTemplate.class);
            ValueOperations<String,String> ops = mock(ValueOperations.class);
            when(redis.opsForValue()).thenReturn(ops);
            when(ops.get(anyString())).thenAnswer(c -> values.get(c.getArgument(0)));
            doAnswer(c -> { values.put(c.getArgument(0), c.getArgument(1)); return null; })
                    .when(ops).set(anyString(), anyString(), any(Duration.class));
            when(ops.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenAnswer(c -> {
                boolean won = values.putIfAbsent(c.getArgument(0), c.getArgument(1)) == null;
                if (!won) contended.countDown(); return won;
            });
            when(redis.execute(any(RedisScript.class), anyList(), any(Object[].class))).thenAnswer(c -> {
                List<String> keys = c.getArgument(1); String token = c.getArgument(2);
                return values.remove(keys.getFirst(), token) ? 1L : 0L;
            });
            ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
            when(provider.getIfAvailable()).thenReturn(redis);
            cache = new HotDataCacheService(provider, new ObjectMapper());
            for (int i = 0; i < 20; i++) rows.add(new Store(i+1, "store-"+i, "", 4.5, 100+i,
                    3, 20, "30分钟", "", "[]", "", "address", 30+i*.001, 114.0, 1, "[1]", 7, 1, 1, "now", 30000));
            when(stores.listAll()).thenAnswer(c -> { storeLoads.incrementAndGet(); return rows; });
            when(stores.listRecommended()).thenReturn(rows);
            when(stores.findById(anyLong())).thenAnswer(c -> rows.stream().filter(row -> row.id() == (long)c.getArgument(0)).findFirst());
            service = new StoreService(stores, goods, mock(GoodsSpecDao.class), seckills,
                    new ObjectMapper(), cache, mock(EmployeeDao.class));
        }
    }

    @Test void oneThousandCoordinatesReuseSourceDataWithCorrectPerRequestDistance() {
        var home = new Fixture();
        for (int i = 0; i < 1000; i++) home.service.listStores(null, null, null);
        double isolated = 100.0 * (1000-home.storeLoads.get()) / 1000;
        var f = new Fixture();
        for (int i = 0; i < 1000; i++) {
            double lat = 30+i*.001, lon = 114+i*.001;
            var result = f.service.listStores(null, lat, lon);
            assertEquals(f.rows.getFirst().withDistance(lat, lon).distance(), result.getFirst().distance());
        }
        int coldLoads = f.storeLoads.get();
        for (int i = 0; i < 1000; i++) f.service.listStores(null, 30+i*.001, 114+i*.001);
        int repeatLoads = f.storeLoads.get()-coldLoads;
        int homeMisses = 0;
        for (int i = 0; i < 1000; i++) {
            f.service.listStores(null, 30+i*.001, 114+i*.001);
            int before = f.storeLoads.get(); f.service.listStores(null, null, null);
            if (f.storeLoads.get() != before) homeMisses++;
        }
        double cold = 100.0*(1000-coldLoads)/1000, repeat = 100.0*(1000-repeatLoads)/1000;
        double interleaved = 100.0*(1000-homeMisses)/1000;
        System.out.printf(Locale.ROOT,"[RT-36/hits] coordinates=1000 stores=20 home-isolated=%.2f%% geo-cold=%.2f%% geo-repeat=%.2f%% home-interleaved=%.2f%% cold-loads=%d repeat-loads=%d%n",
                isolated,cold,repeat,interleaved,coldLoads,repeatLoads);
        assertTrue(cold >= 99, "coordinate changes must reuse the shared source");
        assertTrue(repeat >= 99); assertTrue(interleaved >= 99);
    }

    @Test void dynamicStoreDetailQueriesCannotEvictHomeAndCategories() {
        var f = new Fixture(); var categoryLoads = new AtomicInteger();
        f.cache.get("categories", TEXT, () -> { categoryLoads.incrementAndGet(); return "categories"; });
        f.service.listStores(null, null, null);
        for (int i = 1; i <= 2000; i++) f.service.storeDetail(i);
        assertEquals("categories", f.cache.get("categories", TEXT, () -> { categoryLoads.incrementAndGet(); return "categories"; }));
        f.service.listStores(null, null, null);
        System.out.println("[RT-36/hot] dynamic-details=2000 category-loads="+categoryLoads.get()+" home-source-loads="+f.storeLoads.get());
        assertEquals(1, categoryLoads.get()); assertEquals(1, f.storeLoads.get());
    }

    @Test void sharedCandidatesStillApplyCurrentRadiusCoordinatesAndLimit() {
        var f = new Fixture();
        assertEquals(3, f.service.recommendedStores(1,3,30.0,114.0).size());
        assertTrue(f.service.recommendedStores(1,3,30.1,114.0).isEmpty());
        var far = f.service.recommendedStores(20,10,30.1,114.0);
        assertEquals(10, far.size());
        assertNotEquals("0.0km", far.getFirst().distance());
        verify(f.stores, times(1)).listRecommended();
        var goods = new com.example.takeout.model.Goods(1,1,"goods","",10,20,"",1,0,100,0,100,4.5,"",true,1,"now");
        var special = new com.example.takeout.model.SpecialGoods(goods,"store","old");
        when(f.goods.listSpecialGoods(anyInt())).thenReturn(List.of(special,special));
        when(f.goods.listTopGoods(anyInt())).thenReturn(List.of(special,special));
        var seckill = new com.example.takeout.model.Seckill.SeckillView(1,1,"goods","",20,10,100,0,"start","end",1,"store","old",60);
        when(f.seckills.listActiveViews(anyInt(),anyString())).thenReturn(List.of(seckill,seckill));
        String near = f.rows.getFirst().withDistance(30.0,114.0).distance();
        String away = f.rows.getFirst().withDistance(30.1,114.0).distance();
        assertEquals(near,f.service.listSpecialGoods(1,30.0,114.0).getFirst().storeDistance());
        assertEquals(2,f.service.listSpecialGoods(2,30.1,114.0).size());
        assertEquals(away,f.service.listSpecialGoods(1,30.1,114.0).getFirst().storeDistance());
        assertEquals(near,f.service.rankGoods(1,30.0,114.0).getFirst().storeDistance());
        assertEquals(away,f.service.rankGoods(1,30.1,114.0).getFirst().storeDistance());
        assertEquals(near,f.service.listSeckills(1,30.0,114.0).getFirst().storeDistance());
        assertEquals(away,f.service.listSeckills(1,30.1,114.0).getFirst().storeDistance());
        verify(f.goods,times(1)).listSpecialGoods(50); verify(f.goods,times(1)).listTopGoods(50);
        verify(f.seckills,times(1)).listActiveViews(eq(50),anyString());
        verify(f.stores,times(1)).findById(1);
        System.out.println("[RT-36/projection] radius-and-limit-applied-per-request=true current-distance=true source-loads=1-per-family store-lookup=1");
    }

    @Test void foreignSlotOwnerDoesNotMakeAnUnrelatedQueryWaitForRebuild() throws Exception {
        for (boolean hasValue : new boolean[]{false,true}) {
            var f = new Fixture(); var entered = new CountDownLatch(1); var release = new CountDownLatch(1);
            assertEquals(f.cache.storageKey("stores:Aa"), f.cache.storageKey("stores:BB"));
            try (var pool = Executors.newSingleThreadExecutor()) {
                var first = pool.submit(() -> f.cache.get("stores:Aa", TEXT, () -> {
                    entered.countDown(); try { assertTrue(release.await(3,TimeUnit.SECONDS)); }
                    catch(InterruptedException e){throw new RuntimeException(e);} return "A";
                }));
                try {
                    assertTrue(entered.await(3,TimeUnit.SECONDS));
                    if (hasValue) f.values.put(f.cache.storageKey("stores:Aa"), new ObjectMapper().createObjectNode()
                            .put("key","stores:Aa").put("value","\"old-A\"").toString());
                    long start=System.nanoTime(); assertEquals("B",f.cache.get("stores:BB",TEXT,()->"B"));
                    long elapsed=TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start);
                    System.out.println("[RT-37/foreign] slot-has-value="+hasValue+" wait-ms="+elapsed+" result=B owner-still-active="+(release.getCount()==1));
                    assertTrue(elapsed < 200,"an unrelated slot owner must not consume the 500ms wait");
                } finally {release.countDown();}
                assertEquals("A",first.get(3,TimeUnit.SECONDS));
            }
        }
    }

    @Test void sameBusinessKeyStillWaitsAndReusesTheOwnersResult() throws Exception {
        var f = new Fixture(); var entered=new CountDownLatch(1);var release=new CountDownLatch(1);var loads=new AtomicInteger();
        try(var pool=Executors.newFixedThreadPool(2)) {
            var first=pool.submit(()->f.cache.get("categories",TEXT,()->{
                loads.incrementAndGet();entered.countDown();try {assertTrue(release.await(3,TimeUnit.SECONDS));}
                catch(InterruptedException e){throw new RuntimeException(e);}return "shared";
            }));
            assertTrue(entered.await(3,TimeUnit.SECONDS));
            var second=pool.submit(()->f.cache.get("categories",TEXT,()->{loads.incrementAndGet();return "unexpected";}));
            try {assertTrue(f.contended.await(3,TimeUnit.SECONDS));}finally{release.countDown();}
            assertEquals("shared",first.get(3,TimeUnit.SECONDS));assertEquals("shared",second.get(3,TimeUnit.SECONDS));
            assertEquals(1,loads.get());System.out.println("[RT-37/same] concurrent=2 loader-calls=1 shared-result=true");
        }
    }
}
