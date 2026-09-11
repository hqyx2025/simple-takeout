package com.example.takeout.model;

import java.util.List;

/**
 * 评价（tags/images 以 JSON 字符串存储，DTO 输出转为 List）
 */
public record Review(
        long id,
        long orderId,
        long storeId,
        long goodsId,
        long userId,
        String userName,
        int rating,
        String content,
        String tags,
        String images,
        int anonymous,
        String reply,
        String replyTime,
        String createTime
) {
    public record ReviewView(
            long id,
            long orderId,
            long storeId,
            long goodsId,
            long userId,
            String userName,
            int rating,
            String content,
            List<String> tags,
            List<String> images,
            int anonymous,
            String reply,
            String replyTime,
            String createTime
    ) {
    }

    public ReviewView toView(List<String> tagsList, List<String> imagesList) {
        return new ReviewView(id, orderId, storeId, goodsId, userId, userName, rating, content,
                tagsList, imagesList, anonymous, reply, replyTime, createTime);
    }
}
