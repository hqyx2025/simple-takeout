package com.example.takeout.model;

/**
 * 优惠券领取台账（按活动唯一，终身限领一次；领取中心/限领审计依据）。
 */
public record UserCoupon(
        long id,
        long userId,
        long storeId,
        String name,
        double threshold,
        double amount,
        String claimTime,
        String expireTime
) {
}
