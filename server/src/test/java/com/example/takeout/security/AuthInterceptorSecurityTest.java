package com.example.takeout.security;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
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

    @Test
    void rejectsRequestWithoutBearerToken() {
        JwtUtil jwtUtil = mock(JwtUtil.class);
        UserDao userDao = mock(UserDao.class);
        AuthInterceptor interceptor = new AuthInterceptor(jwtUtil, userDao);
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getMethod()).thenReturn("GET");
        when(request.getHeader("Authorization")).thenReturn(null);

        BizException error = assertThrows(BizException.class,
                () -> interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));

        assertEquals(401, error.getCode());
    }

    @Test
    void rejectsInvalidBearerToken() {
        JwtUtil jwtUtil = mock(JwtUtil.class);
        UserDao userDao = mock(UserDao.class);
        AuthInterceptor interceptor = new AuthInterceptor(jwtUtil, userDao);
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getMethod()).thenReturn("GET");
        when(request.getHeader("Authorization")).thenReturn("Bearer invalid");
        when(jwtUtil.parseToken(anyString())).thenThrow(new IllegalArgumentException("bad token"));

        BizException error = assertThrows(BizException.class,
                () -> interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));

        assertEquals(401, error.getCode());
    }

    @Test
    void rejectsTokenWhenRoleChanged() {
        JwtUtil jwtUtil = mock(JwtUtil.class);
        UserDao userDao = mock(UserDao.class);
        AuthInterceptor interceptor = new AuthInterceptor(jwtUtil, userDao);
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getMethod()).thenReturn("GET");
        when(request.getHeader("Authorization")).thenReturn("Bearer token");
        io.jsonwebtoken.Claims claims = mock(io.jsonwebtoken.Claims.class);
        when(jwtUtil.parseToken("token")).thenReturn(claims);
        when(jwtUtil.getUserId(claims)).thenReturn(1L);
        when(jwtUtil.getRole(claims)).thenReturn(0);
        when(userDao.findById(1L)).thenReturn(Optional.of(
                new User(1, "merchant", "", "13600136000", "", 1, 0, "now")));

        BizException error = assertThrows(BizException.class,
                () -> interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));

        assertEquals(401, error.getCode());
    }

    @Test
    void acceptsValidTokenAndStoresIdentityAttributes() {
        JwtUtil jwtUtil = mock(JwtUtil.class);
        UserDao userDao = mock(UserDao.class);
        AuthInterceptor interceptor = new AuthInterceptor(jwtUtil, userDao);
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getMethod()).thenReturn("GET");
        when(request.getHeader("Authorization")).thenReturn("Bearer token");
        io.jsonwebtoken.Claims claims = mock(io.jsonwebtoken.Claims.class);
        when(jwtUtil.parseToken("token")).thenReturn(claims);
        when(jwtUtil.getUserId(claims)).thenReturn(2L);
        when(jwtUtil.getRole(claims)).thenReturn(2);
        when(userDao.findById(2L)).thenReturn(Optional.of(
                new User(2, "admin", "", "13100131000", "", 2, 0, "now")));

        assertTrue(interceptor.preHandle(request, mock(HttpServletResponse.class), new Object()));
        verify(request).setAttribute(AuthInterceptor.ATTR_USER_ID, 2L);
        verify(request).setAttribute(AuthInterceptor.ATTR_ROLE, 2);
    }
}
