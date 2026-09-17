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
    /** 骑手未设置配送半径时的默认值（米）：25 公里。 */
    public static final int DEFAULT_DELIVERY_RADIUS_METERS = 25000;

    /** 服务端可接受的半径下限/上限（米）：过小/过大由前端弹窗确认，这里只挡明显非法值。 */
    public static final int MIN_DELIVERY_RADIUS_METERS = 1000;
    public static final int MAX_DELIVERY_RADIUS_METERS = 200000;

    /** 接单位置是否已设置（没有位置就无法判定能接哪些单）。 */
    public boolean hasLocation() {
        return latitude != null && longitude != null
                && Double.isFinite(latitude) && Double.isFinite(longitude)
                && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
                && !(latitude == 0 && longitude == 0);
    }
}
