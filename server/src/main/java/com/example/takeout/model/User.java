package com.example.takeout.model;

import com.fasterxml.jackson.annotation.JsonIgnore;

/**
 * 用户（角色：0=用户 1=商户 2=管理端，与客户端 UserRole 对齐）
 */
public record User(
        long id,
        String username,
        String avatar,
        String phone,
        String password,
        int role,
        double balance,
        String createTime,
        /** 最后一次改密时间（空=从未改密）；仅服务端签发 token 用，@JsonIgnore 不返回前端。 */
        @JsonIgnore String passwordChangedAt
) {
    /** 兼容旧调用点的 8 参构造（视为从未改密）。 */
    public User(long id, String username, String avatar, String phone, String password,
                int role, double balance, String createTime) {
        this(id, username, avatar, phone, password, role, balance, createTime, "");
    }

    /**
     * 脱敏视图：不返回密码
     */
    public User safe() {
        return new User(id, username, avatar, phone, "", role, balance, createTime, passwordChangedAt);
    }
}
