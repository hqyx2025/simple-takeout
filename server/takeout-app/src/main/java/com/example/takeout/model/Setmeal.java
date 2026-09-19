package com.example.takeout.model;

import java.util.List;

/**
 * 套餐（组合购）：一份套餐价打包多件商品，items 为组件明细。
 */
public record Setmeal(
        long id,
        long storeId,
        String name,
        String description,
        double price,
        double originalPrice,
        String image,
        int status,
        String createTime,
        List<SetmealItem> items
) {
    public Setmeal withItems(List<SetmealItem> items) {
        return new Setmeal(id, storeId, name, description, price, originalPrice, image, status, createTime, items);
    }
}
