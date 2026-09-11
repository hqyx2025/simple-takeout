package com.example.takeout.model;

/**
 * 骑手档案（四端改造：users.role=3 对应的骑手业务资料）
 */
public record Rider(
        long id,
        long userId,
        String name,
        String phone,
        int online,
        int totalOrders,
        double totalIncome,
        int status,
        String createTime
) {
}
