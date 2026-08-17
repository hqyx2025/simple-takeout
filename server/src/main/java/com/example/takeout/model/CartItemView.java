package com.example.takeout.model;

/**
 * 购物车接口返回视图，直接提供前端渲染所需的商品和店铺信息。
 */
public record CartItemView(
        long id,
        long goodsId,
        long storeId,
        String storeName,
        int quantity,
        Goods goods
) {
}
