package com.example.takeout.model;

import java.util.List;

/**
 * 评价（tags 以 JSON 字符串存储，DTO 输出转为 List）
 */
public record Review(
        long id,
        long storeId,
        long userId,
        String userName,
        int rating,
        String content,
        String tags,
        String createTime
) {
    public record ReviewView(
            long id,
            long storeId,
            long userId,
            String userName,
            int rating,
            String content,
            List<String> tags,
            String createTime
    ) {
    }

    public ReviewView toView(List<String> tagsList) {
        return new ReviewView(id, storeId, userId, userName, rating, content, tagsList, createTime);
    }
}
