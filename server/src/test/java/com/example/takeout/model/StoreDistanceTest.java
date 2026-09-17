package com.example.takeout.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 店铺距离判定：只有「用户有定位 且 店铺有坐标」才算真实距离，否则必须是「未知距离」。
 * 历史缺陷：缺坐标时沿用库里的 distance 字符串，主页「附近推荐」把没有坐标的店铺当成
 * 「离你很近」（实测：武汉的店在沈阳用户端显示 0.2km，且能通过 2 公里筛选）。
 */
class StoreDistanceTest {

    private Store storeWith(Double latitude, Double longitude) {
        return new Store(1L, "测试店", "", 4.5, 0, 3, 20, "30分钟", "0.2km", "[]", "",
                "武汉市光谷", latitude, longitude, 1, "[1]", 99L, 1, 0, "", 0);
    }

    @Test
    void distanceIsComputedOnlyWhenBothSidesHaveCoordinates() {
        Store computed = storeWith(30.5928, 114.3055).withDistance(30.5946, 114.3055);
        assertTrue(computed.distance().endsWith("km"), computed.distance());

        // 店铺没有坐标：不能沿用历史 distance（否则会被当成 0.2km 的附近店铺）
        assertEquals(Store.UNKNOWN_DISTANCE, storeWith(null, null).withDistance(30.5946, 114.3055).distance());

        // 用户没有定位：同样不可判断
        assertEquals(Store.UNKNOWN_DISTANCE, storeWith(30.5928, 114.3055).withDistance(null, null).distance());
    }
}
