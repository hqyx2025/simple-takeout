package com.example.takeout.model;

import java.util.List;

/**
 * 店铺（tags/categoryIds 以 JSON 字符串存储，DTO 输出转为 List）
 */
public record Store(
        long id,
        String name,
        String image,
        double rating,
        int monthlySales,
        double deliveryFee,
        double minOrder,
        String deliveryTime,
        String distance,
        String tags,
        String notice,
        int categoryId,
        String categoryIds,
        long ownerId,
        int status,
        int recommended,
        String createTime
) {
    /**
     * 视图模型：tags/categoryIds 解析为 List 便于客户端直接使用
     */
    public record StoreView(
            long id,
            String name,
            String image,
            double rating,
            int monthlySales,
            double deliveryFee,
            double minOrder,
            String deliveryTime,
            String distance,
            List<String> tags,
            String notice,
            int categoryId,
            List<Integer> categoryIds,
            long ownerId,
            int status,
            int recommended
    ) {
    }

    public StoreView toView(List<String> tagsList, List<Integer> categoryIdsList) {
        return new StoreView(id, name, image, rating, monthlySales, deliveryFee, minOrder,
                deliveryTime, distance, tagsList, notice, categoryId, categoryIdsList, ownerId, status, recommended);
    }
}
