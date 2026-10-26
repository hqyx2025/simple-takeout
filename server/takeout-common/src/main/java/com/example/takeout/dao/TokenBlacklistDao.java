package com.example.takeout.dao;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/**
 * Token 黑名单：登出后的 token 立即失效（这是「退出登录」真正生效的地方）。
 *
 * <p>存数据库而不是 Redis：登出必须做到「Redis 挂了也照样生效」，而且本地开发常不开 Redis。
 * 过期数据由应用定时清理，退出与刷新不扫描全表。</p>
 */
@Repository
public class TokenBlacklistDao {

    private final JdbcTemplate jdbc;

    public TokenBlacklistDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** 拉黑一个 jti（重复登出幂等）。 */
    public void revoke(String jti, long userId, long expiresAtMillis, String reason, String now) {
        jdbc.update("INSERT INTO token_blacklist(jti, user_id, reason, expires_at, create_time) " +
                        "VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE reason = VALUES(reason), " +
                        "expires_at = GREATEST(expires_at, VALUES(expires_at))",
                jti, userId, reason, expiresAtMillis, now);
    }

    public boolean isRevoked(String jti) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM token_blacklist WHERE jti = ? AND reason NOT LIKE 'ac:%'",
                Integer.class, jti);
        return count != null && count > 0;
    }

    public void insertRefreshToken(String tokenHash, long userId, String familyId, long expiresAtMillis, String now) {
        jdbc.update("INSERT INTO token_blacklist(jti, user_id, reason, expires_at, create_time) VALUES(?,?,?,?,?)",
                tokenHash, userId, "rf:" + familyId, expiresAtMillis, now);
    }

    public void trackAccessToken(String jti, long userId, String familyId, long expiresAtMillis, String now) {
        jdbc.update("INSERT INTO token_blacklist(jti, user_id, reason, expires_at, create_time) VALUES(?,?,?,?,?)",
                jti, userId, "ac:" + familyId, expiresAtMillis, now);
    }

    public Optional<RefreshTokenRecord> findRefreshTokenForUpdate(String tokenHash) {
        return jdbc.query("SELECT user_id, reason, expires_at FROM token_blacklist WHERE jti = ? FOR UPDATE",
                (rs, row) -> new RefreshTokenRecord(rs.getLong("user_id"), rs.getString("reason"),
                        rs.getLong("expires_at")), tokenHash).stream().findFirst();
    }

    public int consumeRefreshToken(String tokenHash, long userId, String familyId, long expiresAtMillis) {
        return jdbc.update("UPDATE token_blacklist SET reason = ?, expires_at = ? " +
                        "WHERE jti = ? AND user_id = ? AND reason = ?",
                "ru:" + familyId, expiresAtMillis, tokenHash, userId, "rf:" + familyId);
    }

    public void extendConsumedRefreshFamily(long userId, String familyId, long expiresAtMillis) {
        jdbc.update("UPDATE token_blacklist SET expires_at = ? WHERE user_id = ? AND reason = ?",
                expiresAtMillis, userId, "ru:" + familyId);
    }

    public void revokeRefreshFamily(long userId, String familyId) {
        jdbc.update("UPDATE token_blacklist SET reason = ? WHERE user_id = ? AND reason IN (?, ?)",
                "rx:" + familyId, userId, "rf:" + familyId, "ru:" + familyId);
        jdbc.update("UPDATE token_blacklist SET reason = 'refresh-revoked' " +
                        "WHERE user_id = ? AND reason = ?",
                userId, "ac:" + familyId);
    }

    public void revokeRefreshTokensForUser(long userId) {
        jdbc.update("UPDATE token_blacklist SET reason = 'rx:password' " +
                        "WHERE user_id = ? AND LEFT(reason, 3) IN ('rf:', 'ru:')",
                userId);
    }

    public record RefreshTokenRecord(long userId, String reason, long expiresAtMillis) {
    }

    public int deleteExpiredBatch() {
        return jdbc.update("DELETE FROM token_blacklist WHERE expires_at < ? LIMIT 1000", System.currentTimeMillis());
    }
}
