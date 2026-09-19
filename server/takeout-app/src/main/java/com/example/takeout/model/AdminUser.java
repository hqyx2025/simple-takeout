package com.example.takeout.model;

/** 管理端用户/商户账号视图，不包含密码。 */
public record AdminUser(
        long id,
        String username,
        String phone,
        int role,
        int status,
        double balance,
        int storeCount,
        String createTime
) {
}
