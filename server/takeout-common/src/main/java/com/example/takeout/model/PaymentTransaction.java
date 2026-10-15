package com.example.takeout.model;

import java.math.BigDecimal;

public record PaymentTransaction(
        long id,
        long orderId,
        long userId,
        String channel,
        BigDecimal amount,
        String outTradeNo,
        String providerTransactionId,
        String status,
        String paymentUrl,
        String createTime,
        String notifyTime,
        String paymentMode
) {
    public PaymentTransaction(long id, long orderId, long userId, String channel, BigDecimal amount,
                              String outTradeNo, String providerTransactionId, String status, String paymentUrl,
                              String createTime, String notifyTime) {
        this(id, orderId, userId, channel, amount, outTradeNo, providerTransactionId, status, paymentUrl,
                createTime, notifyTime, "QR");
    }
}
