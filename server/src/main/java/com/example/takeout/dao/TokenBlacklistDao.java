package com.example.takeout.dao;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * Token 黑名单：登出后的 token 立即失效（这是「退出登录」真正生效的地方）。
 *
 * <p>存数据库而不是 Redis：登出必须做到「Redis 挂了也照样生效」，而且本地开发常不开 Redis。
 * 记一行只占几十字节，过期时间与 token 自身一致，由 {@link #revoke} 顺带清理。</p>
 */
@Repository
public class TokenBlacklistDao {

    private final JdbcTemplate jdbc;

    public TokenBlacklistDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * 拉黑一个 jti（重复登出幂等）。
     *
     * <p>ponytail: 过期条目在每次登出时批量清理，不另起定时任务。上限是「没人登出则过期行滞留」，
     * 量级受 72 小时 token 寿命约束；若登出频率极低又想清理，加个 @Scheduled 即可。</p>
     */
    public void revoke(String jti, long userId, long expiresAtMillis, String reason, String now) {
        jdbc.update("DELETE FROM token_blacklist WHERE expires_at < ?", System.currentTimeMillis());
        jdbc.update("INSERT IGNORE INTO token_blacklist(jti, user_id, reason, expires_at, create_time) " +
                "VALUES(?,?,?,?,?)", jti, userId, reason, expiresAtMillis, now);
    }

    public boolean isRevoked(String jti) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM token_blacklist WHERE jti = ?", Integer.class, jti);
        return count != null && count > 0;
    }
}