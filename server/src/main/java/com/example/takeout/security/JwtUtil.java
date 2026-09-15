package com.example.takeout.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.UUID;

/**
 * JWT 工具：签发与解析 Token
 * 载荷包含 userId、role、jti（供登出拉黑）与 pwdAt（改密时间，供改密后旧 token 立即失效）
 * 过期时间可配置
 */
@Component
public class JwtUtil {

    /** 改密时间声明名：值为 users.password_changed_at 原文（yyyy-MM-dd HH:mm:ss，空=从未改密）。 */
    public static final String CLAIM_PWD_AT = "pwdAt";

    private final SecretKey key;
    private final long expireMillis;

    public JwtUtil(@Value("${takeout.jwt.secret}") String secret,
                   @Value("${takeout.jwt.expire-hours}") long expireHours) {
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expireMillis = expireHours * 3600_000L;
    }

    /**
     * 签发 Token（不含改密时间，等价于「从未改密」）
     */
    public String generateToken(long userId, int role) {
        return generateToken(userId, role, "");
    }

    /**
     * 签发 Token
     *
     * @param passwordChangedAt 签发时刻该用户的改密时间；改密后凡早于它的 token 一律失效
     */
    public String generateToken(long userId, int role, String passwordChangedAt) {
        Date now = new Date();
        return Jwts.builder()
                .id(UUID.randomUUID().toString())
                .subject(String.valueOf(userId))
                .claim("role", role)
                .claim(CLAIM_PWD_AT, passwordChangedAt == null ? "" : passwordChangedAt)
                .issuedAt(now)
                .expiration(new Date(now.getTime() + expireMillis))
                .signWith(key)
                .compact();
    }

    /**
     * 解析 Token，非法/过期抛出异常
     */
    public Claims parseToken(String token) {
        return Jwts.parser()
                .verifyWith(key)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    public long getUserId(Claims claims) {
        return Long.parseLong(claims.getSubject());
    }

    public int getRole(Claims claims) {
        Object role = claims.get("role");
        return role instanceof Number n ? n.intValue() : 0;
    }

    /** token 唯一标识（jti）；历史版本签发的 token 没有该声明，此时返回 null。 */
    public String getJti(Claims claims) {
        return claims.getId();
    }

    /** 签发时用户的改密时间；缺失按「从未改密」处理。 */
    public String getPasswordChangedAt(Claims claims) {
        Object value = claims.get(CLAIM_PWD_AT);
        return value instanceof String s ? s : "";
    }

    /** token 过期时刻（毫秒）；黑名单条目按它清理与设 TTL。 */
    public long getExpiresAtMillis(Claims claims) {
        Date expiration = claims.getExpiration();
        return expiration == null ? System.currentTimeMillis() : expiration.getTime();
    }
}
