package com.example.takeout.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 下单统一限制为 500 公里；历史商户半径不再提前阻止下单，缺坐标仍允许浏览。
 */
class StoreDeliveryRadiusTest {

    private Store store(Double latitude, Double longitude, int radius) {
        return new Store(1, "店", "", 4.5, 0, 3.0, 20, "30分钟", "1.0km", "[]", "",
                "地址", latitude, longitude, 1, "[1]", 99, 1, 0, "2026-01-01 00:00:00", radius);
    }

    @Test
    void historicalMerchantRadiusDoesNotBlockCheckout() {
        Store s = store(39.90, 116.40, 1000);
        assertTrue(s.canDeliver(39.95, 116.40), "不再按历史商户半径提前拒绝下单");
    }

    @Test
    void allowsAddressWithinRadius() {
        Store s = store(39.90, 116.40, 5000);
        assertTrue(s.canDeliver(39.91, 116.40));
    }

    @Test
    void orderLimitIsFiveHundredKilometers() {
        assertTrue(store(39.90, 116.40, 0).canDeliver(39.95, 116.40), "约 5.5km 在默认 30 公里内");
        assertTrue(store(39.90, 116.40, 0).canDeliver(40.15, 116.40), "约 27.8km 在默认 30 公里内");
        assertTrue(store(39.90, 116.40, 0).canDeliver(40.25, 116.40));
        assertTrue(store(0.0, 108.0, 1000).canDeliver(Math.toDegrees(500.0 / 6371), 108.0));
        assertFalse(store(0.0, 108.0, 1000000).canDeliver(Math.toDegrees(500.001 / 6371), 108.0));
    }

    @Test
    void missingCoordinatesNeverBlock() {
        assertTrue(store(39.90, 116.40, 5000).canDeliver(null, null), "收货地址无坐标不拦截");
        assertTrue(store(null, null, 0).canDeliver(39.91, 116.40), "门店无坐标不拦截");
    }
}
