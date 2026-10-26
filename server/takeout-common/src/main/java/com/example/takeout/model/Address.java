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
        Double longitude,
        String mapAddress,
        String doorDetail,
        String tag
) {
    /** 兼容旧调用方：无坐标地址。 */
    public Address(long id, long userId, String name, String phone, String detail,
                   int isDefault, String createTime) {
        this(id, userId, name, phone, detail, isDefault, createTime, null, null, null, null, "");
    }

    /** 兼容已有坐标调用方：结构化地址为空时 detail 仍是完整地址。 */
    public Address(long id, long userId, String name, String phone, String detail,
                   int isDefault, String createTime, Double latitude, Double longitude) {
        this(id, userId, name, phone, detail, isDefault, createTime, latitude, longitude, null, null, "");
    }

    /** 兼容尚未传地址标签的结构化地址调用方。 */
    public Address(long id, long userId, String name, String phone, String detail,
                   int isDefault, String createTime, Double latitude, Double longitude,
                   String mapAddress, String doorDetail) {
        this(id, userId, name, phone, detail, isDefault, createTime, latitude, longitude,
                mapAddress, doorDetail, "");
    }
}
