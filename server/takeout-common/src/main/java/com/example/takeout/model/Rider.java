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
        int deliveryRadius,
        Double latitude,
        Double longitude,
        String locationAddress,
        String createTime
) {
    public static final int DEFAULT_DELIVERY_RADIUS_METERS = 3000;

    public static final int MIN_DELIVERY_RADIUS_METERS = 1000;
    public static final int MAX_DELIVERY_RADIUS_METERS = 5000;

    /** 新写入由服务校验，历史值在读取时按生效范围解释，无须改写已有数据。 */
    @Override
    public int deliveryRadius() {
        return deliveryRadius <= 0 ? DEFAULT_DELIVERY_RADIUS_METERS
                : Math.clamp(deliveryRadius, MIN_DELIVERY_RADIUS_METERS, MAX_DELIVERY_RADIUS_METERS);
    }

    /** 接单位置是否已设置（没有位置就无法判定能接哪些单）。 */
    public boolean hasLocation() {
        return latitude != null && longitude != null
                && Double.isFinite(latitude) && Double.isFinite(longitude)
                && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
                && !(latitude == 0 && longitude == 0);
    }
}
