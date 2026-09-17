package com.example.takeout.model;

/**
 * 营销活动（type：DISCOUNT 折扣{discountRate} / NEW_USER 新客立减{reduceAmount} / GIFT 满赠{threshold+giftGoodsId}）。
 */
public record MarketingActivity(
        long id,
        long storeId,
        String type,
        String title,
        double discountRate,
        double reduceAmount,
        double threshold,
        long giftGoodsId,
        String startTime,
        String endTime,
        int status,
        String createTime
) {
}
