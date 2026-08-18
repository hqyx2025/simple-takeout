package com.example.takeout.model;

import java.util.List;
import java.util.Locale;

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
        String address,
        Double latitude,
        Double longitude,
        int categoryId,
        String categoryIds,
        long ownerId,
        int status,
        int recommended,
        String createTime
) {
    /** 兼容旧测试数据与旧调用方：历史店铺没有地址坐标。 */
    public Store(long id, String name, String image, double rating, int monthlySales, double deliveryFee,
                 double minOrder, String deliveryTime, String distance, String tags, String notice,
                 int categoryId, String categoryIds, long ownerId, int status, int recommended,
                 String createTime) {
        this(id, name, image, rating, monthlySales, deliveryFee, minOrder, deliveryTime, distance, tags, notice,
                "", null, null, categoryId, categoryIds, ownerId, status, recommended, createTime);
    }

    /** 按用户当前位置计算距离；无坐标的存量店铺使用规范化后的历史距离。 */
    public Store withDistance(Double userLatitude, Double userLongitude) {
        String nextDistance = normalizeDistance(distance);
        if (validCoordinates(userLatitude, userLongitude) && validCoordinates(latitude, longitude)) {
            double distanceKm = haversine(userLatitude, userLongitude, latitude, longitude);
            nextDistance = formatDistance(distanceKm);
        }
        return new Store(id, name, image, rating, monthlySales, deliveryFee, minOrder, deliveryTime,
                nextDistance, tags, notice, address, latitude, longitude, categoryId, categoryIds,
                ownerId, status, recommended, createTime);
    }

    public static String normalizeDistance(String value) {
        if (value == null || value.isBlank()) {
            return "未知距离";
        }
        try {
            String numeric = value.toLowerCase(Locale.ROOT).replace("km", "").trim();
            return formatDistance(Double.parseDouble(numeric));
        } catch (NumberFormatException ignored) {
            return value;
        }
    }

    private static boolean validCoordinates(Double latitude, Double longitude) {
        return latitude != null && longitude != null
                && Double.isFinite(latitude) && Double.isFinite(longitude)
                && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
    }

    private static double haversine(double firstLatitude, double firstLongitude,
                                    double secondLatitude, double secondLongitude) {
        double latitudeDelta = Math.toRadians(secondLatitude - firstLatitude);
        double longitudeDelta = Math.toRadians(secondLongitude - firstLongitude);
        double firstLatitudeRad = Math.toRadians(firstLatitude);
        double secondLatitudeRad = Math.toRadians(secondLatitude);
        double value = Math.pow(Math.sin(latitudeDelta / 2), 2)
                + Math.cos(firstLatitudeRad) * Math.cos(secondLatitudeRad)
                * Math.pow(Math.sin(longitudeDelta / 2), 2);
        return 6371.0 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
    }

    private static String formatDistance(double distanceKm) {
        return String.format(Locale.ROOT, "%.1fkm", Math.max(0, distanceKm));
    }

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
            String address,
            Double latitude,
            Double longitude,
            int categoryId,
            List<Integer> categoryIds,
            long ownerId,
            int status,
            int recommended
    ) {
    }

    public StoreView toView(List<String> tagsList, List<Integer> categoryIdsList) {
        return new StoreView(id, name, image, rating, monthlySales, deliveryFee, minOrder,
                deliveryTime, distance, tagsList, notice, address, latitude, longitude,
                categoryId, categoryIdsList, ownerId, status, recommended);
    }
}
