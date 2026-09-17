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
        String createTime,
        int deliveryRadius
) {
    /** 兼容旧测试数据与旧调用方：历史店铺没有地址坐标。 */
    public Store(long id, String name, String image, double rating, int monthlySales, double deliveryFee,
                 double minOrder, String deliveryTime, String distance, String tags, String notice,
                 int categoryId, String categoryIds, long ownerId, int status, int recommended,
                 String createTime) {
        this(id, name, image, rating, monthlySales, deliveryFee, minOrder, deliveryTime, distance, tags, notice,
                "", null, null, categoryId, categoryIds, ownerId, status, recommended, createTime, 0);
    }

    /**
     * 距离未知的展示文案：没有用户定位、或店铺本身没有坐标时使用。
     * 「附近」筛选靠解析 distance 里的数字，未知距离不带数字 → 自然被排除。
     */
    public static final String UNKNOWN_DISTANCE = "未知距离";

    /**
     * 按用户当前位置计算距离。
     * 只有「用户有定位 且 店铺有坐标」才能算出真实距离；否则返回 {@link #UNKNOWN_DISTANCE}。
     * 历史实现会在缺坐标时沿用库里的 distance 字符串，于是没有坐标的店铺（例如新建时没定位）
     * 会被当成「离你很近」出现在主页附近推荐里（实测：武汉的店在沈阳的用户端显示 0.2km）。
     */
    public Store withDistance(Double userLatitude, Double userLongitude) {
        if (!validCoordinates(userLatitude, userLongitude) || !validCoordinates(latitude, longitude)) {
            return new Store(id, name, image, rating, monthlySales, deliveryFee, minOrder, deliveryTime,
                    UNKNOWN_DISTANCE, tags, notice, address, latitude, longitude, categoryId, categoryIds,
                    ownerId, status, recommended, createTime, deliveryRadius);
        }
        double distanceKm = haversine(userLatitude, userLongitude, latitude, longitude);
        return new Store(id, name, image, rating, monthlySales, deliveryFee, minOrder, deliveryTime,
                formatDistance(distanceKm), tags, notice, address, latitude, longitude, categoryId, categoryIds,
                ownerId, status, recommended, createTime, deliveryRadius);
    }

    /** 商户未填配送半径时使用的默认值（米）：2 公里。 */
    public static final int DEFAULT_DELIVERY_RADIUS_METERS = 2000;

    /**
     * 能否配送到用户当前位置。
     * 半径取商户填写的值；**商户没填（0）按默认 2 公里**，不再表示"不限"。
     * 用户没定位、或门店没坐标时无法判断，返回 true（是否展示由调用方按距离另行决定）。
     */
    public boolean canDeliver(Double userLatitude, Double userLongitude) {
        if (!validCoordinates(userLatitude, userLongitude) || !validCoordinates(latitude, longitude)) {
            return true;
        }
        int effectiveRadius = deliveryRadius > 0 ? deliveryRadius : DEFAULT_DELIVERY_RADIUS_METERS;
        return haversine(userLatitude, userLongitude, latitude, longitude) * 1000 <= effectiveRadius;
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
        // 浮点误差在近对跖点会让 value 略大于 1 → sqrt(1-value) 得到 NaN → 距离渲染成「NaNkm」，
        // 且 NaN 参与距离筛选比较恒为 false，该店会被静默过滤，故先夹到 [0,1]
        double safe = Math.min(1.0, Math.max(0.0, value));
        return 6371.0 * 2 * Math.atan2(Math.sqrt(safe), Math.sqrt(1 - safe));
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
            int recommended,
            int deliveryRadius,
            boolean deliverable
    ) {
    }

    public StoreView toView(List<String> tagsList, List<Integer> categoryIdsList) {
        return toView(tagsList, categoryIdsList, null, null);
    }

    public StoreView toView(List<String> tagsList, List<Integer> categoryIdsList,
                            Double userLatitude, Double userLongitude) {
        return new StoreView(id, name, image, rating, monthlySales, deliveryFee, minOrder,
                deliveryTime, distance, tagsList, notice, address, latitude, longitude,
                categoryId, categoryIdsList, ownerId, status, recommended,
                deliveryRadius, canDeliver(userLatitude, userLongitude));
    }
}
