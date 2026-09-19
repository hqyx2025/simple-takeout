package com.example.takeout.model;

/**
 * 菜品规格（多规格 SKU）：同一菜品下每个规格独立定价与库存。
 * stock 使用与 goods 相同的乐观锁口径（version + 条件更新）防超卖。
 */
public record GoodsSpec(
        long id,
        long goodsId,
        String name,
        double price,
        int stock,
        int version,
        int sort,
        int status,
        String createTime
) {
}
