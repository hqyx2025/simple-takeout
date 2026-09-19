package com.example.takeout.model;

/**
 * 下单请求里的套餐项（setmealId + 数量）。
 */
public record SetmealOrder(long setmealId, int quantity) {
}
