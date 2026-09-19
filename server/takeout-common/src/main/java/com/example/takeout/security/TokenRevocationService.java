package com.example.takeout.security;

import com.example.takeout.dao.TokenBlacklistDao;
import io.jsonwebtoken.Claims;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * Token 吊销：把 token 的 jti 记入黑名单，使「退出登录」立刻生效。
 *
 * <p>只有 jti 落库才能吊销——用户表里没有 token 记录，也枚举不出已签发的 token。
 * 解析失败（伪造/已过期）的 token 无需拉黑：它本来就过不了认证。</p>
 */
@Service
public class TokenRevocationService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final JwtUtil jwtUtil;
    private final TokenBlacklistDao tokenBlacklistDao;

    public TokenRevocationService(JwtUtil jwtUtil, TokenBlacklistDao tokenBlacklistDao) {
        this.jwtUtil = jwtUtil;
        this.tokenBlacklistDao = tokenBlacklistDao;
    }

    /**
     * 拉黑一个 token（幂等）。
     *
     * @return 是否确实写入（token 非法/过期时返回 false，调用方无需报错）
     */
    public boolean revoke(String token, String reason) {
        if (token == null || token.isBlank()) {
            return false;
        }
        Claims claims;
        try {
            claims = jwtUtil.parseToken(token);
        } catch (Exception e) {
            return false;
        }
        String jti = jwtUtil.getJti(claims);
        if (jti == null || jti.isBlank()) {
            return false;
        }
        tokenBlacklistDao.revoke(jti, jwtUtil.getUserId(claims), jwtUtil.getExpiresAtMillis(claims),
                reason, LocalDateTime.now().format(FMT));
        return true;
    }

    /** 该 jti 是否已被吊销（jti 为空的历史 token 无法吊销，按未吊销处理）。 */
    public boolean isRevoked(String jti) {
        if (jti == null || jti.isBlank()) {
            return false;
        }
        return tokenBlacklistDao.isRevoked(jti);
    }
}