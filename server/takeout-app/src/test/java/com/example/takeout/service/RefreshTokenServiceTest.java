package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.TokenBlacklistDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RefreshTokenServiceTest {

    @Test
    void issueStoresOnlyDigestAndAThirtyDayExpiry() {
        TokenBlacklistDao tokenDao = mock(TokenBlacklistDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        Claims claims = mock(Claims.class);
        when(jwtUtil.parseToken("access-token")).thenReturn(claims);
        when(jwtUtil.getJti(claims)).thenReturn("access-jti");
        when(jwtUtil.getExpiresAtMillis(claims)).thenReturn(System.currentTimeMillis() + 60_000);
        when(jwtUtil.getUserId(claims)).thenReturn(7L);
        when(jwtUtil.getPasswordChangedAt(claims)).thenReturn("");
        UserDao users = mock(UserDao.class);
        when(users.findByIdForUpdate(7)).thenReturn(Optional.of(new User(7, "user", "", "13800138000", "",
                0, 20, "now")));
        RefreshTokenService service = new RefreshTokenService(tokenDao, users, jwtUtil);
        long before = System.currentTimeMillis();

        String raw = service.issue(7, "access-token");

        assertEquals(43, raw.length());
        org.mockito.ArgumentCaptor<String> hash = org.mockito.ArgumentCaptor.forClass(String.class);
        org.mockito.ArgumentCaptor<String> reason = org.mockito.ArgumentCaptor.forClass(String.class);
        org.mockito.ArgumentCaptor<Long> expiry = org.mockito.ArgumentCaptor.forClass(Long.class);
        verify(tokenDao).trackAccessToken(eq("access-jti"), eq(7L), anyString(), anyLong(), anyString());
        verify(tokenDao).insertRefreshToken(hash.capture(), eq(7L), reason.capture(), expiry.capture(), anyString());
        assertEquals(64, hash.getValue().length());
        assertNotEquals(raw, hash.getValue());
        assertTrue(reason.getValue().matches("[0-9a-f]{24}"));
        assertTrue(expiry.getValue() >= before + 30L * 24 * 60 * 60 * 1000 - 1000);
    }

    @Test
    void refreshConsumesOldTokenAndIssuesNextTokenInSameFamily() throws Exception {
        String raw = "current-refresh";
        String family = "0123456789abcdef01234567";
        TokenBlacklistDao tokenDao = mock(TokenBlacklistDao.class);
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        Claims claims = mock(Claims.class);
        when(tokenDao.findRefreshTokenForUpdate(sha256(raw))).thenReturn(Optional.of(
                new TokenBlacklistDao.RefreshTokenRecord(7, "rf:" + family, System.currentTimeMillis() + 60_000)));
        when(tokenDao.consumeRefreshToken(eq(sha256(raw)), eq(7L), eq(family), anyLong())).thenReturn(1);
        when(userDao.findById(7)).thenReturn(Optional.of(new User(7, "user", "", "13800138000", "",
                0, 20, "now", "2026-10-01 00:00:00")));
        when(jwtUtil.generateToken(7, 0, "2026-10-01 00:00:00")).thenReturn("new-access");
        when(jwtUtil.parseToken("new-access")).thenReturn(claims);
        when(jwtUtil.getJti(claims)).thenReturn("new-access-jti");
        when(jwtUtil.getExpiresAtMillis(claims)).thenReturn(System.currentTimeMillis() + 60_000);

        RefreshTokenService.RefreshResult result = new RefreshTokenService(tokenDao, userDao, jwtUtil).refresh(raw);

        assertEquals("new-access", result.token());
        assertNotEquals(raw, result.refreshToken());
        verify(tokenDao).consumeRefreshToken(eq(sha256(raw)), eq(7L), eq(family), anyLong());
        verify(tokenDao).extendConsumedRefreshFamily(eq(7L), eq(family), anyLong());
        verify(tokenDao).trackAccessToken(eq("new-access-jti"), eq(7L), eq(family), anyLong(), anyString());
        org.mockito.ArgumentCaptor<String> nextHash = org.mockito.ArgumentCaptor.forClass(String.class);
        verify(tokenDao).insertRefreshToken(nextHash.capture(), eq(7L), eq(family), anyLong(), anyString());
        assertEquals(sha256(result.refreshToken()), nextHash.getValue());
    }

    @Test
    void passwordResetBetweenCredentialCheckAndRefreshIssueRejectsTheOldLogin() {
        TokenBlacklistDao tokenDao = mock(TokenBlacklistDao.class);
        UserDao users = mock(UserDao.class);
        byte[] signingBytes = new byte[32];
        new java.security.SecureRandom().nextBytes(signingBytes);
        JwtUtil jwt = new JwtUtil(java.util.Base64.getEncoder().encodeToString(signingBytes), 72);
        String staleAccess = jwt.generateToken(7, 0, "");
        when(users.findByIdForUpdate(7)).thenReturn(Optional.of(new User(7, "user", "", "13800138000", "",
                0, 20, "now", "2026-10-14 12:00:00")));

        assertThrows(BizException.class, () -> new RefreshTokenService(tokenDao, users, jwt).issue(7, staleAccess));

        verify(tokenDao, never()).insertRefreshToken(anyString(), anyLong(), anyString(), anyLong(), anyString());
        verify(tokenDao, never()).trackAccessToken(anyString(), anyLong(), anyString(), anyLong(), anyString());
    }

    @Test
    void replayRevokesTheWholeFamily() {
        String family = "0123456789abcdef01234567";
        TokenBlacklistDao tokenDao = mock(TokenBlacklistDao.class);
        when(tokenDao.findRefreshTokenForUpdate(anyString())).thenReturn(Optional.of(
                new TokenBlacklistDao.RefreshTokenRecord(7, "ru:" + family, System.currentTimeMillis() + 60_000)));

        BizException error = assertThrows(BizException.class,
                () -> new RefreshTokenService(tokenDao, mock(UserDao.class), mock(JwtUtil.class))
                        .refresh("already-used"));

        assertEquals(401, error.getCode());
        verify(tokenDao).revokeRefreshFamily(7, family);
        verify(tokenDao, never()).insertRefreshToken(anyString(), anyLong(), anyString(), anyLong(), anyString());
    }

    @Test
    void expiredTokenDoesNotIssueOrRevokeAnything() {
        String family = "0123456789abcdef01234567";
        TokenBlacklistDao tokenDao = mock(TokenBlacklistDao.class);
        when(tokenDao.findRefreshTokenForUpdate(anyString())).thenReturn(Optional.of(
                new TokenBlacklistDao.RefreshTokenRecord(7, "rf:" + family, 1)));

        assertThrows(BizException.class,
                () -> new RefreshTokenService(tokenDao, mock(UserDao.class), mock(JwtUtil.class))
                        .refresh("expired"));

        verify(tokenDao, never()).consumeRefreshToken(anyString(), anyLong(), anyString(), anyLong());
        verify(tokenDao, never()).revokeRefreshFamily(anyLong(), anyString());
    }

    private static String sha256(String token) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(token.getBytes(StandardCharsets.UTF_8)));
    }
}
