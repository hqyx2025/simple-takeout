package com.example.takeout.model;

/**
 * 购物车接口返回视图，直接提供前端渲染所需的商品、规格和店铺信息。
 * price 为实际结算单价：多规格取规格价，无规格取菜品价。
 */
public record CartItemView(
        long id,
        long goodsId,
        long storeId,
        String storeName,
        long specId,
        String specName,
        double price,
        int stock,
        int quantity,
        Goods goods
) {
}
