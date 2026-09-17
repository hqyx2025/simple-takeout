package com.example.takeout.model;

/**
 * 套餐明细项（组件商品）。
 */
public record SetmealItem(
        long id,
        long setmealId,
        long goodsId,
        String goodsName,
        int quantity
) {
}
