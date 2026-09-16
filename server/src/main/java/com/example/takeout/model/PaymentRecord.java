package com.example.takeout.model;

/**
 * 支付/退款明细（type：PAY 支付 / REFUND 退款；channel：BALANCE/ALIPAY/WECHAT）。
 */
public record PaymentRecord(
        long id,
        long orderId,
        long userId,
        double amount,
        String type,
        String channel,
        String status,
        String createTime
) {
}
