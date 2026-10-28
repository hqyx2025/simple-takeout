package com.example.takeout.model;

import java.math.BigDecimal;
import java.util.List;

/** 售后事实：金额为元，REFUNDED 才计入退款及商户负担累计。 */
public record RefundRecord(
        long id, long orderId, long userId, long merchantId,
        String reasonType, String reason, BigDecimal amount, String status,
        String applyTime, String processTime, String rejectReason,
        List<String> evidenceImages, List<String> merchantEvidenceImages, String merchantResponse,
        int appealCount, String appealReason, List<String> appealImages, int originalEscrow, int settledBefore,
        BigDecimal merchantAmount, BigDecimal platformAmount, String refundTime
) {
    public RefundRecord(long id, long orderId, long userId, long merchantId,
                        String reasonType, String reason, double amount, String status,
                        String applyTime, String processTime, String rejectReason) {
        this(id, orderId, userId, merchantId, reasonType, reason, BigDecimal.valueOf(amount).setScale(2, java.math.RoundingMode.HALF_UP),
                status, applyTime, processTime, rejectReason, List.of(), List.of(), "", 0, "", List.of(), 0, 0,
                BigDecimal.ZERO.setScale(2), BigDecimal.ZERO.setScale(2), "");
    }
}
