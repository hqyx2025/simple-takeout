package com.example.takeout.model;

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
        String createTime
) {
    /**
     * 脱敏视图：不返回密码
     */
    public User safe() {
        return new User(id, username, avatar, phone, "", role, balance, createTime);
    }
}
