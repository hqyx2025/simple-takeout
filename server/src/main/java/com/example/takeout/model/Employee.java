package com.example.takeout.model;

/**
 * 门店员工（按店分配角色，status=1 启用；员工只能操作被分配的店铺）。
 */
public record Employee(
        long id,
        long storeId,
        long userId,
        String username,
        String phone,
        String roleName,
        int status,
        String createTime
) {
}
