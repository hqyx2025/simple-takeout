package com.example.takeout.model;

/**
 * 收货地址
 */
public record Address(
        long id,
        long userId,
        String name,
        String phone,
        String detail,
        int isDefault,
        String createTime
) {
}
