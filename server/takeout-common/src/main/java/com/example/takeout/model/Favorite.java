package com.example.takeout.model;

/**
 * 收藏
 */
public record Favorite(
        long id,
        long userId,
        long storeId,
        String createTime
) {
}
