package com.example.takeout.security;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import io.jsonwebtoken.Claims;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AuthInterceptorSecurityTest {

    private final JwtUtil jwtUtil = mock(JwtUtil.class);
    private final UserDao userDao = mock(UserDao.class);
    private final TokenRevocationService revocationService = mock(TokenRevocationService.class);
    private final AuthInterceptor interceptor = new AuthInterceptor(jwtUtil, userDao, revocationService);

    private HttpServletRequest bearerRequest(String token) {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getMethod()).thenReturn("GET");
        when(request.getHeader("Authorization")).thenReturn("Bearer " + token);
        return request;
    }

    @Test
    void rejectsRequestWithoutBearerToken() {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getMethod()).thenReturn("GET");
        when(request.getHeader("Authorization")).thenReturn(null);

        BizException error = assertThrows(BizException.class,
                () -> interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));

        assertEquals(401, error.getCode());
    }

    @Test
    void rejectsInvalidBearerToken() {
        HttpServletRequest request = bearerRequest("invalid");
        when(jwtUtil.parseToken(anyString())).thenThrow(new IllegalArgumentException("bad token"));

        BizException error = assertThrows(BizException.class,
                () -> interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));

        assertEquals(401, error.getCode());
    }

    @Test
    void rejectsTokenWhenRoleChanged() {
        HttpServletRequest request = bearerRequest("token");
        Claims claims = mock(Claims.class);
        when(jwtUtil.parseToken("token")).thenReturn(claims);
        when(jwtUtil.getUserId(claims)).thenReturn(1L);
        when(jwtUtil.getRole(claims)).thenReturn(0);
        when(userDao.findById(1L)).thenReturn(Optional.of(
                new User(1, "merchant", "", "13600136000", "", 1, 0, "now")));

        BizException error = assertThrows(BizException.class,
                () -> interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));

        assertEquals(401, error.getCode());
    }

    /** 已登出（jti 进了黑名单）的 token 必须被拒，否则「退出登录」只是前端假象。 */
    @Test
    void rejectsRevokedToken() {
        HttpServletRequest request = bearerRequest("token");
        Claims claims = mock(Claims.class);
        when(jwtUtil.parseToken("token")).thenReturn(claims);
        when(jwtUtil.getJti(claims)).thenReturn("jti-1");
        when(revocationService.isRevoked("jti-1")).thenReturn(true);

        BizException error = assertThrows(BizException.class,
                () -> interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));

        assertEquals(401, error.getCode());
        assertEquals("登录已退出，请重新登录", error.getMessage());
    }

    /** 改密后，签发时间早于改密时间的 token 必须被拒。 */
    @Test
    void rejectsTokenIssuedBeforePasswordChange() {
        HttpServletRequest request = bearerRequest("token");
        Claims claims = mock(Claims.class);
        when(jwtUtil.parseToken("token")).thenReturn(claims);
        when(jwtUtil.getUserId(claims)).thenReturn(2L);
        when(jwtUtil.getRole(claims)).thenReturn(2);
        when(jwtUtil.getPasswordChangedAt(claims)).thenReturn("2026-09-01 09:00:00");
        when(userDao.findById(2L)).thenReturn(Optional.of(
                new User(2, "admin", "", "13100131000", "", 2, 0, "now", "2026-09-01 10:00:00")));

        BizException error = assertThrows(BizException.class,
                () -> interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));

        assertEquals(401, error.getCode());
        assertEquals("密码已修改，请重新登录", error.getMessage());
    }

    @Test
    void acceptsValidTokenAndStoresIdentityAttributes() {
        HttpServletRequest request = bearerRequest("token");
        Claims claims = mock(Claims.class);
        when(jwtUtil.parseToken("token")).thenReturn(claims);
        when(jwtUtil.getUserId(claims)).thenReturn(2L);
        when(jwtUtil.getRole(claims)).thenReturn(2);
        when(jwtUtil.getPasswordChangedAt(claims)).thenReturn("2026-09-01 10:00:00");
        when(userDao.findById(2L)).thenReturn(Optional.of(
                new User(2, "admin", "", "13100131000", "", 2, 0, "now", "2026-09-01 10:00:00")));

        assertTrue(interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));
        verify(request).setAttribute(AuthInterceptor.ATTR_USER_ID, 2L);
        verify(request).setAttribute(AuthInterceptor.ATTR_ROLE, 2);
    }

    /** 从未改密的账号（password_changed_at 为空）不受改密校验影响。 */
    @Test
    void acceptsTokenWhenAccountNeverChangedPassword() {
        HttpServletRequest request = bearerRequest("token");
        Claims claims = mock(Claims.class);
        when(jwtUtil.parseToken("token")).thenReturn(claims);
        when(jwtUtil.getUserId(claims)).thenReturn(1L);
        when(jwtUtil.getRole(claims)).thenReturn(0);
        when(userDao.findById(1L)).thenReturn(Optional.of(
                new User(1, "用户", "", "13800138000", "", 0, 20, "now")));

        assertTrue(interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));
    }
}