package com.example.takeout.security;

import com.example.takeout.dao.TokenBlacklistDao;
import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class TokenRevocationServiceTest {

    private final JwtUtil jwtUtil = mock(JwtUtil.class);
    private final TokenBlacklistDao dao = mock(TokenBlacklistDao.class);
    private final TokenRevocationService service = new TokenRevocationService(jwtUtil, dao);

    @Test
    void revokeStoresJtiWithTokenExpiry() {
        Claims claims = mock(Claims.class);
        when(jwtUtil.parseToken("token")).thenReturn(claims);
        when(jwtUtil.getJti(claims)).thenReturn("jti-1");
        when(jwtUtil.getUserId(claims)).thenReturn(5L);
        when(jwtUtil.getExpiresAtMillis(claims)).thenReturn(1_700_000_000_000L);

        assertTrue(service.revoke("token", "logout"));

        verify(dao).revoke(eq("jti-1"), eq(5L), eq(1_700_000_000_000L), eq("logout"), anyString());
    }

    /** 伪造或已过期的 token 本来就过不了认证，不必（也无法）拉黑。 */
    @Test
    void revokeIgnoresUnparsableToken() {
        when(jwtUtil.parseToken("bad")).thenThrow(new IllegalArgumentException("bad token"));

        assertFalse(service.revoke("bad", "logout"));

        verifyNoInteractions(dao);
    }

    @Test
    void revokeIgnoresTokenWithoutJti() {
        Claims claims = mock(Claims.class);
        when(jwtUtil.parseToken("old-token")).thenReturn(claims);
        when(jwtUtil.getJti(claims)).thenReturn(null);

        assertFalse(service.revoke("old-token", "logout"));

        verifyNoInteractions(dao);
    }

    @Test
    void blankJtiIsNeverConsideredRevoked() {
        assertFalse(service.isRevoked(""));
        verifyNoInteractions(dao);
    }

    @Test
    void isRevokedDelegatesToDao() {
        when(dao.isRevoked("jti-1")).thenReturn(true);

        assertTrue(service.isRevoked("jti-1"));
    }
}