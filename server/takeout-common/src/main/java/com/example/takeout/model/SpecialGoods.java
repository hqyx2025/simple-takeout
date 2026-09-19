package com.example.takeout.model;

/** 首页特价团购商品视图，附带店铺信息用于展示和跳转。 */
public record SpecialGoods(
        Goods goods,
        String storeName,
        String storeDistance
) {
}
