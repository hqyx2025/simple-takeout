package com.example.takeout.model;

/**
 * 商品（status：1=上架 0=下架；stock=库存，version=乐观锁；merchantCategoryId=商户分类，0=未分组）
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
        int status,
        String createTime
) {
}
