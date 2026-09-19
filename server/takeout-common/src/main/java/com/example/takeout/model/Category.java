package com.example.takeout.model;

/**
 * 分类（type：PLATFORM平台分类/MERCHANT商户分类；merchantId=商户用户ID，平台分类为 0）
 */
public record Category(
        long id,
        String name,
        String icon,
        String color,
        String type,
        long merchantId,
        int sort,
        int status
) {
}
