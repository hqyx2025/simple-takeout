package com.example.takeout.model;

/**
 * 收货地址（latitude/longitude 为地图选点坐标，可为空=存量地址）。
 */
public record Address(
        long id,
        long userId,
        String name,
        String phone,
        String detail,
        int isDefault,
        String createTime,
        Double latitude,
        Double longitude
) {
    /** 兼容旧调用方：无坐标地址。 */
    public Address(long id, long userId, String name, String phone, String detail,
                   int isDefault, String createTime) {
        this(id, userId, name, phone, detail, isDefault, createTime, null, null);
    }
}
