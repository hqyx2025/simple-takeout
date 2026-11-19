package com.example.takeout.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class StoreDeliveryRadiusTest {

    private Store store(Double latitude, Double longitude, int radius) {
        return new Store(1, "店", "", 4.5, 0, 3.0, 20, "30分钟", "1.0km", "[]", "",
                "地址", latitude, longitude, 1, "[1]", 99, 1, 0, "2026-01-01 00:00:00", radius);
    }

    @Test
    void merchantRadiusLimitsDelivery() {
        Store s = store(39.90, 116.40, 1000);
        assertFalse(s.canDeliver(39.95, 116.40));
    }

    @Test
    void allowsAddressWithinRadius() {
        Store s = store(39.90, 116.40, 5000);
        assertTrue(s.canDeliver(39.91, 116.40));
    }

    @Test
    void defaultsToTenAndClampsHistoricalRadiusToFifteen() {
        Store defaults = store(0.0, 108.0, 0);
        assertEquals(10000, defaults.effectiveDeliveryRadiusMeters());
        assertTrue(defaults.canDeliver(Math.toDegrees(10.0 / 6371), 108.0));
        assertFalse(defaults.canDeliver(Math.toDegrees(10.001 / 6371), 108.0));
        Store legacy = store(0.0, 108.0, 500000);
        assertTrue(legacy.canDeliver(Math.toDegrees(15.0 / 6371), 108.0));
        assertFalse(legacy.canDeliver(Math.toDegrees(15.001 / 6371), 108.0));
    }

    @Test
    void missingCoordinatesNeverBlock() {
        assertTrue(store(39.90, 116.40, 5000).canDeliver(null, null), "收货地址无坐标不拦截");
        assertTrue(store(null, null, 0).canDeliver(39.91, 116.40), "门店无坐标不拦截");
    }
}
