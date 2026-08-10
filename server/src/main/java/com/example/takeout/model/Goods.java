package com.example.takeout.model;

/**
 * 商品（status：1=上架 0=下架）
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
        int sales,
        double rating,
        String tag,
        int status,
        String createTime
) {
}
