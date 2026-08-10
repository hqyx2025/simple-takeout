package com.example.takeout.model;

/**
 * 优惠券（status：0=可用 1=已用 2=过期）
 */
public record Coupon(
        long id,
        long userId,
        long storeId,
        String name,
        double threshold,
        double amount,
        int status,
        String expireTime,
        String source,
        String createTime
) {
}
