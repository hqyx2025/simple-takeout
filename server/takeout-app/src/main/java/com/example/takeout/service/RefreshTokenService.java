package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.TokenBlacklistDao;
import com.example.takeout.dao.TokenBlacklistDao.RefreshTokenRecord;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import io.jsonwebtoken.Claims;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Optional;
import java.util.UUID;

/** Rotating refresh credentials; only SHA-256 digests are stored. */
@Service
public class RefreshTokenService {

    private static final long LIFETIME_MILLIS = 30L * 24 * 60 * 60 * 1000;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final SecureRandom RANDOM = new SecureRandom();

    private final TokenBlacklistDao tokenDao;
    private final UserDao userDao;
    private final JwtUtil jwtUtil;

    public RefreshTokenService(TokenBlacklistDao tokenDao, UserDao userDao, JwtUtil jwtUtil) {
        this.tokenDao = tokenDao;
        this.userDao = userDao;
        this.jwtUtil = jwtUtil;
    }

    @Transactional
    public String issue(long userId, String accessToken) {
        Claims claims = jwtUtil.parseToken(accessToken);
        // Serialize with password changes: either their revocation includes this family,
        // or credentials checked before that change cannot create a new family afterward.
        User user = userDao.findByIdForUpdate(userId).orElseThrow(RefreshTokenService::unauthorized);
        String passwordChangedAt = user.passwordChangedAt() == null ? "" : user.passwordChangedAt();
        if (user.status() != 1 || jwtUtil.getUserId(claims) != userId
                || jwtUtil.getRole(claims) != user.role()
                || !passwordChangedAt.equals(jwtUtil.getPasswordChangedAt(claims))) {
            throw unauthorized();
        }
        String familyId = UUID.randomUUID().toString().replace("-", "").substring(0, 24);
        trackAccessToken(accessToken, userId, familyId);
        return issueRefreshToken(userId, familyId);
    }

    @Transactional(noRollbackFor = BizException.class)
    public RefreshResult refresh(String rawToken) {
        if (rawToken == null || rawToken.isBlank() || rawToken.length() > 128) {
            throw unauthorized();
        }
        String hash = hash(rawToken);
        Optional<RefreshTokenRecord> found = tokenDao.findRefreshTokenForUpdate(hash);
        if (found.isEmpty()) {
            throw unauthorized();
        }
        RefreshTokenRecord current = found.get();
        String familyId = familyId(current.reason());
        if (familyId == null) {
            throw unauthorized();
        }
        if (current.reason().startsWith("ru:")) {
            tokenDao.revokeRefreshFamily(current.userId(), familyId);
            throw unauthorized();
        }
        if (!current.reason().equals("rf:" + familyId) || current.expiresAtMillis() <= System.currentTimeMillis()) {
            throw unauthorized();
        }

        User user = userDao.findById(current.userId()).orElseThrow(RefreshTokenService::unauthorized);
        if (user.status() != 1) {
            tokenDao.revokeRefreshFamily(current.userId(), familyId);
            throw unauthorized();
        }

        long expiresAt = System.currentTimeMillis() + LIFETIME_MILLIS;
        if (tokenDao.consumeRefreshToken(hash, current.userId(), familyId, expiresAt) != 1) {
            throw unauthorized();
        }
        tokenDao.extendConsumedRefreshFamily(current.userId(), familyId, expiresAt);
        String next = newToken();
        tokenDao.insertRefreshToken(hash(next), current.userId(), familyId, expiresAt,
                LocalDateTime.now().format(FMT));
        String accessToken = jwtUtil.generateToken(user.id(), user.role(), user.passwordChangedAt());
        trackAccessToken(accessToken, user.id(), familyId);
        return new RefreshResult(accessToken, next);
    }

    @Transactional(noRollbackFor = BizException.class)
    public void revoke(String rawToken) {
        if (rawToken == null || rawToken.isBlank() || rawToken.length() > 128) {
            return;
        }
        Optional<RefreshTokenRecord> found = tokenDao.findRefreshTokenForUpdate(hash(rawToken));
        if (found.isEmpty()) {
            return;
        }
        RefreshTokenRecord current = found.get();
        String familyId = familyId(current.reason());
        if (familyId != null) {
            tokenDao.revokeRefreshFamily(current.userId(), familyId);
        }
    }

    private String issueRefreshToken(long userId, String familyId) {
        String token = newToken();
        tokenDao.insertRefreshToken(hash(token), userId, familyId,
                System.currentTimeMillis() + LIFETIME_MILLIS, LocalDateTime.now().format(FMT));
        return token;
    }

    private void trackAccessToken(String token, long userId, String familyId) {
        Claims claims = jwtUtil.parseToken(token);
        tokenDao.trackAccessToken(jwtUtil.getJti(claims), userId, familyId,
                jwtUtil.getExpiresAtMillis(claims), LocalDateTime.now().format(FMT));
    }

    private String newToken() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String hash(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }

    private String familyId(String reason) {
        if (reason == null || reason.length() != 27 || reason.charAt(2) != ':' ||
                !reason.startsWith("rf:") && !reason.startsWith("ru:") && !reason.startsWith("rx:")) {
            return null;
        }
        return reason.substring(3);
    }

    private static BizException unauthorized() {
        return new BizException(401, "登录已过期，请重新登录");
    }

    public record RefreshResult(String token, String refreshToken) {
    }
}
