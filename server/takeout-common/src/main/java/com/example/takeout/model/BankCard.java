package com.example.takeout.model;

/**
 * 用户已绑定的银行卡（钱包页展示）。
 *
 * 安全口径：完整卡号在数据库仅保存服务端 AES-GCM 密文，不进入这个实体；
 * 列表和新增响应只输出掩码 cardNoMasked（**** **** **** 1234）。
 *
 * 注意：掩码必须作为**record 组件**存在。Jackson 序列化 record 时只认组件，
 * 额外写一个 cardNoMasked() 方法**不会**出现在 JSON 里（本项目已踩过：
 * 接口少了这个字段，前端 Text(undefined) 直接渲染空白）。
 */
public record BankCard(
        long id,
        long userId,
        String bankName,
        String cardType,
        String cardNoMasked,
        int isDefault,
        int status,
        String createTime
) {
}
