package com.example.takeout.model;

/**
 * 退款记录（status：PENDING待审批/APPROVED已同意/REJECTED已拒绝/REFUNDED已退款）
 * 数字状态机映射：申请后订单 status=6（退款中）；审批通过后 escrow_status=2 表达退款完成。
 */
public record RefundRecord(
        long id,
        long orderId,
        long userId,
        long merchantId,
        String reason,
        double amount,
        String status,
        String applyTime,
        String processTime,
        String rejectReason
) {
}
