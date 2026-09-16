package com.example.takeout.model;

/**
 * 退款原因（结构化枚举）：用户申请退款时从固定项中选一个，可另附备注文字。
 * 空值归入 OTHER（兼容旧客户端只传文本）；显式传入的非法 code 返回 null（由调用方拒绝）。
 */
public enum RefundReason {
    NOT_RECEIVED("NOT_RECEIVED", "未收到餐"),
    QUALITY_ISSUE("QUALITY_ISSUE", "餐品质量问题"),
    WRONG_ITEM("WRONG_ITEM", "商品不符"),
    DONOT_WANT("DONOT_WANT", "不想要了"),
    OTHER("OTHER", "其他");

    private final String code;
    private final String label;

    RefundReason(String code, String label) {
        this.code = code;
        this.label = label;
    }

    public String code() {
        return code;
    }

    public String label() {
        return label;
    }

    /** null/空白 → OTHER（旧客户端）；显式非法 code → null。 */
    public static RefundReason fromCode(String code) {
        if (code == null || code.isBlank()) {
            return OTHER;
        }
        for (RefundReason r : values()) {
            if (r.code.equals(code)) {
                return r;
            }
        }
        return null;
    }
}
