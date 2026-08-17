package com.example.takeout.model;

/** 平台监管使用的商品视图，包含所属店铺信息。 */
public record AdminProduct(
        long id,
        long storeId,
        String storeName,
        String name,
        String description,
        double price,
        double originalPrice,
        String image,
        int categoryId,
        long merchantCategoryId,
        int stock,
        int sales,
        double rating,
        String tag,
        int status,
        String createTime
) {
}
