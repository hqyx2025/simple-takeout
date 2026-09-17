package com.example.takeout.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 商户配送半径契约：商户填了按商户的（米），没填（0）按默认 2 公里；缺坐标时无法判断不拦截。
 */
class StoreDeliveryRadiusTest {

    private Store store(Double latitude, Double longitude, int radius) {
        return new Store(1, "店", "", 4.5, 0, 3.0, 20, "30分钟", "1.0km", "[]", "",
                "地址", latitude, longitude, 1, "[1]", 99, 1, 0, "2026-01-01 00:00:00", radius);
    }

    @Test
    void blocksAddressBeyondRadius() {
        Store s = store(39.90, 116.40, 1000);
        assertFalse(s.canDeliver(39.95, 116.40), "距离约 5.5km 超出 1km 半径应拒绝");
    }

    @Test
    void allowsAddressWithinRadius() {
        Store s = store(39.90, 116.40, 5000);
        assertTrue(s.canDeliver(39.91, 116.40));
    }

    @Test
    void blankRadiusFallsBackToDefaultTwoKilometers() {
        // 商户没填半径（0）时按默认 2 公里，不再表示"不限"
        assertTrue(store(39.90, 116.40, 0).canDeliver(39.91, 116.40), "约 1.1km 在默认 2 公里内");
        assertFalse(store(39.90, 116.40, 0).canDeliver(39.95, 116.40), "约 5.5km 超出默认 2 公里");
    }

    @Test
    void missingCoordinatesNeverBlock() {
        assertTrue(store(39.90, 116.40, 5000).canDeliver(null, null), "收货地址无坐标不拦截");
        assertTrue(store(null, null, 0).canDeliver(39.91, 116.40), "门店无坐标不拦截");
    }
}
