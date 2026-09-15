package com.example.takeout.service;

import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.BankCardDao;
import com.example.takeout.dao.CouponDao;
import com.example.takeout.dao.FavoriteDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.ReviewDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.model.Store;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 搜索命中口径（纯单元测试，不起 Spring 上下文）。
 *
 * 除结果正确外，这里还守住一条性能契约：搜索**不得**逐店查商品。
 * 历史实现是 storeDao.listAll() 里对每家店调一次 goodsDao.listByStore（41 店 → 42 次查询），
 * 一旦有人改回这个写法，countGoodsQueriesPerStore 就会 > 0 让用例失败。
 */
class UserCenterSearchTest {

    private static Store store(long id, String name, String notice) {
        return new Store(id, name, "img.png", 4.5, 100, 3.0, 20.0, "30分钟", "1.0km",
                "[]", notice, 1, "[]", 9L, 1, 0, "2026-01-01 00:00:00");
    }

    /** 记录逐店查询次数的替身：搜索路径上这个数字必须恒为 0。 */
    private static class CountingGoodsDao extends GoodsDao {
        int perStoreQueryCount = 0;
        final List<Long> matchingStoreIds;

        CountingGoodsDao(List<Long> matchingStoreIds) {
            super(null, null);
            this.matchingStoreIds = matchingStoreIds;
        }
        @Override
        public List<Long> listStoreIdsByNameLike(String keyword) {
            return matchingStoreIds;
        }

        @Override
        public List<com.example.takeout.model.Goods> listByStore(long storeId) {
            perStoreQueryCount++;
            return List.of();
        }
    }

    private static class FakeStoreDao extends StoreDao {
        private final List<Store> stores;

        FakeStoreDao(List<Store> stores) {
            super(null);
            this.stores = stores;
        }

        @Override
        public List<Store> listAll() {
            return stores;
        }
    }

    private static UserCenterService service(FakeStoreDao storeDao, CountingGoodsDao goodsDao) {
        return new UserCenterService(null, null, null, null, storeDao, goodsDao, null, new ObjectMapper());
    }

    @Test
    void matchesStoreByName() {
        CountingGoodsDao goodsDao = new CountingGoodsDao(List.of());
        UserCenterService service = service(new FakeStoreDao(List.of(
                store(1, "老王快餐店", ""),
                store(2, "川味小馆", ""))), goodsDao);

        List<Store.StoreView> result = service.search("老王");

        assertEquals(1, result.size());
        assertEquals(1L, result.get(0).id());
    }

    @Test
    void matchesStoreByGoodsName() {
        CountingGoodsDao goodsDao = new CountingGoodsDao(List.of(2L));
        UserCenterService service = service(new FakeStoreDao(List.of(
                store(1, "老王快餐店", ""),
                store(2, "川味小馆", ""))), goodsDao);

        List<Store.StoreView> result = service.search("小龙虾");

        assertEquals(1, result.size());
        assertEquals(2L, result.get(0).id());
    }

    @Test
    void matchesStoreByNotice() {
        CountingGoodsDao goodsDao = new CountingGoodsDao(List.of());
        UserCenterService service = service(new FakeStoreDao(List.of(
                store(1, "老王快餐店", "本店支持开发票"))), goodsDao);

        assertEquals(1, service.search("开发票").size());
    }

    @Test
    void keywordIsCaseInsensitive() {
        CountingGoodsDao goodsDao = new CountingGoodsDao(List.of());
        UserCenterService service = service(new FakeStoreDao(List.of(store(1, "Pizza House", ""))), goodsDao);

        assertEquals(1, service.search("PIZZA").size());
    }

    @Test
    void blankKeywordReturnsEmpty() {
        CountingGoodsDao goodsDao = new CountingGoodsDao(List.of());
        UserCenterService service = service(new FakeStoreDao(List.of(store(1, "老王快餐店", ""))), goodsDao);

        assertTrue(service.search("   ").isEmpty());
        assertTrue(service.search(null).isEmpty());
    }

    /** 性能契约：搜索一次只查一次商品，绝不逐店查。 */
    @Test
    void searchNeverQueriesGoodsPerStore() {
        CountingGoodsDao goodsDao = new CountingGoodsDao(List.of(2L));
        UserCenterService service = service(new FakeStoreDao(List.of(
                store(1, "老王快餐店", ""),
                store(2, "川味小馆", ""),
                store(3, "麻辣烫", ""),
                store(4, "兰州拉面", ""))), goodsDao);

        service.search("小龙虾");

        assertEquals(0, goodsDao.perStoreQueryCount, "搜索不得逐店查商品（N+1 回归）");
    }
}
