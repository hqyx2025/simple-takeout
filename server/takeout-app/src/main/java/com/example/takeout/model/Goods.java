package com.example.takeout.model;

import java.util.List;

/**
 * 商品（status：1=上架 0=下架；stock=库存，version=乐观锁；merchantCategoryId=商户分类，0=未分组）
 * 多规格：specs 非空时 price/stock 为「规格最低价 / 规格库存合计」，下单必须指定 specId。
 */
public record Goods(
        long id,
        long storeId,
        String name,
        String description,
        double price,
        double originalPrice,
        String image,
        int categoryId,
        long merchantCategoryId,
        int stock,
        int version,
        int sales,
        double rating,
        String tag,
        boolean special,
        int status,
        String createTime,
        List<GoodsSpec> specs
) {

    public Goods {
        specs = specs == null ? List.of() : List.copyOf(specs);
    }

    /** 无规格菜品（或仅需基础字段时使用）。 */
    public Goods(long id, long storeId, String name, String description, double price, double originalPrice,
                 String image, int categoryId, long merchantCategoryId, int stock, int version, int sales,
                 double rating, String tag, boolean special, int status, String createTime) {
        this(id, storeId, name, description, price, originalPrice, image, categoryId, merchantCategoryId,
                stock, version, sales, rating, tag, special, status, createTime, List.of());
    }

    /** 是否多规格菜品。 */
    public boolean multiSpec() {
        return !specs.isEmpty();
    }

    public Goods withSpecs(List<GoodsSpec> nextSpecs) {
        return new Goods(id, storeId, name, description, price, originalPrice, image, categoryId,
                merchantCategoryId, stock, version, sales, rating, tag, special, status, createTime, nextSpecs);
    }
}
