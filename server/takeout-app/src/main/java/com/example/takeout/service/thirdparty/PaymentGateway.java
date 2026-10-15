package com.example.takeout.service.thirdparty;

import java.math.BigDecimal;
import java.util.Map;
import java.time.LocalDateTime;

public interface PaymentGateway {

    String channel();

    String createQrPayment(String outTradeNo, String description, BigDecimal amount, LocalDateTime expiresAt);

    default String createAppPayment(String outTradeNo, String description, BigDecimal amount, LocalDateTime expiresAt) {
        throw new UnsupportedOperationException("This payment channel does not support app payments");
    }

    VerifiedNotice verifyNotification(String body, Map<String, String> metadata);

    /** SDK-verifiable query/close prevents a pending external charge from racing cancellation or balance payment. */
    QueryResult query(String outTradeNo);

    void close(String outTradeNo);

    void refund(String outTradeNo, String outRefundNo, BigDecimal amount);

    record QueryResult(boolean paid, boolean closed, VerifiedNotice notice) {
    }

    record VerifiedNotice(String outTradeNo, String providerTransactionId, long amountFen,
                          String currency, boolean paid) {
    }
}
