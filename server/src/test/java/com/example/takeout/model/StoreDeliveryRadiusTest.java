package com.example.takeout.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 商户配送半径契约：radius<=0 不限；地址无坐标的存量情形不拦截；超出半径（米）拒绝。
 */
class StoreDeliveryRadiusTest {

    private Store store(double latitude, double longitude, int radius) {
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
    void unlimitedRadiusOrMissingCoordsNeverBlocks() {
        assertTrue(store(39.90, 116.40, 0).canDeliver(10.0, 10.0), "radius=0 不限");
        assertTrue(store(39.90, 116.40, 5000).canDeliver(null, null), "地址无坐标不拦截");
    }
}
