package com.example.takeout.model;

/** 管理端员工账号视图（当前员工账号对应商户角色）。 */
public record AdminEmployee(
        long id,
        String username,
        String phone,
        int role,
        int status,
        int storeCount,
        String createTime
) {
}
