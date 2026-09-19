package com.example.takeout.service;

import com.example.takeout.dao.EmployeeDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.model.Store;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.function.Supplier;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 首页「附近推荐」的距离必须是按用户定位算出来的。
 * 历史缺陷：recommendedStores 先按坐标算距离并筛选，最后却用 toView(store) 转视图，
 * 该重载会以 null 坐标重算一次 → 距离被覆盖成库里的旧字符串（坐标缺失后变成「未知距离」），
 * 结果是「沈阳用户在武汉店铺上看到 0.2km」这类与定位无关的距离。
 */
class StoreRecommendedDistanceTest {

    private final StoreDao storeDao = mock(StoreDao.class);
    private final HotDataCacheService cache = mock(HotDataCacheService.class);
    private final StoreService storeService = new StoreService(storeDao, mock(GoodsDao.class),
            mock(GoodsSpecDao.class), mock(SeckillDao.class), new ObjectMapper(), cache, mock(EmployeeDao.class));

    @Test
    void recommendedStoresReturnLocationBasedDistance() {
        Store store = new Store(31L, "光谷牛肉粉", "", 4.7, 800, 3, 20, "20分钟", "0.2km", "[]", "",
                "武汉市光谷", 30.5928, 114.3055, 1, "[1]", 99L, 1, 1, "", 0);
        when(storeDao.listRecommended()).thenReturn(List.of(store));
        // 缓存未命中（mock 默认返回 null）时直接执行回源逻辑，才能断言回源产物里的距离
        when(cache.get(any(), any(), any()))
                .thenAnswer(invocation -> ((Supplier<?>) invocation.getArgument(2)).get());

        List<Store.StoreView> views = storeService.recommendedStores(2, 10, 30.5946, 114.3055);

        assertEquals(1, views.size());
        assertTrue(views.get(0).distance().endsWith("km"), views.get(0).distance());
    }

    /**
     * 配送半径判定：商户填了半径就按商户的——半径 5 公里时，8 公里外的用户看不到这家店；
     * 没填（0）按默认 30 公里，同一个 8 公里外的用户就能看到。
     */
    @Test
    void recommendedStoresRespectMerchantDeliveryRadius() {
        Store narrow = new Store(31L, "光谷牛肉粉", "", 4.7, 800, 3, 20, "20分钟", "0.2km", "[]", "",
                "南宁市青秀区", 22.8177, 108.3665, 1, "[1]", 99L, 1, 1, "", 5000);
        when(storeDao.listRecommended()).thenReturn(List.of(narrow));
        when(cache.get(any(), any(), any()))
                .thenAnswer(invocation -> ((Supplier<?>) invocation.getArgument(2)).get());

        // 用户纬度 +0.072 度 ≈ 8 公里
        assertEquals(0, storeService.recommendedStores(20, 10, 22.8897, 108.3665).size());

        Store blank = new Store(31L, "光谷牛肉粉", "", 4.7, 800, 3, 20, "20分钟", "0.2km", "[]", "",
                "南宁市青秀区", 22.8177, 108.3665, 1, "[1]", 99L, 1, 1, "", 0);
        when(storeDao.listRecommended()).thenReturn(List.of(blank));
        assertEquals(1, storeService.recommendedStores(20, 10, 22.8897, 108.3665).size());
    }
}
