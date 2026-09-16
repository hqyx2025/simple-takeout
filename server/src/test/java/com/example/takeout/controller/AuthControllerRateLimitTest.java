package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.model.User;
import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.security.TokenRevocationService;
import com.example.takeout.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 登录限流接线测试：被封禁的 IP 进不了业务；登录失败计数、成功清零。
 */
class AuthControllerRateLimitTest {

    private final AuthService authService = mock(AuthService.class);
    private final LoginRateLimiter limiter = mock(LoginRateLimiter.class);
    private final AuthController controller = new AuthController(authService, limiter,
            mock(TokenRevocationService.class), mock(com.example.takeout.service.thirdparty.SmsSender.class));
    private final AuthController.LoginRequest loginRequest =
            new AuthController.LoginRequest("13800138000", "123456", "USER");

    private HttpServletRequest requestFrom(String ip) {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getRemoteAddr()).thenReturn(ip);
        return request;
    }

    @Test
    void blockedIpIsRejectedBeforeTouchingCredentials() {
        when(limiter.isBlocked("login", "9.9.9.9")).thenReturn(true);

        BizException error = assertThrows(BizException.class,
                () -> controller.login(loginRequest, requestFrom("9.9.9.9")));

        assertEquals(429, error.getCode());
        verify(authService, never()).login(anyString(), anyString(), anyString());
    }

    @Test
    void failedLoginIsCounted() {
        when(authService.login(anyString(), anyString(), anyString()))
                .thenThrow(new BizException("账号或密码错误"));

        assertThrows(BizException.class, () -> controller.login(loginRequest, requestFrom("9.9.9.9")));

        verify(limiter).recordAttempt("login", "9.9.9.9");
        verify(limiter, never()).reset("login", "9.9.9.9");
    }

    @Test
    void successfulLoginClearsFailures() {
        User user = new User(1, "用户", "", "13800138000", "", 0, 20, "now");
        when(authService.login(anyString(), anyString(), anyString()))
                .thenReturn(new AuthService.LoginResult("token", user));

        controller.login(loginRequest, requestFrom("9.9.9.9"));

        verify(limiter).reset("login", "9.9.9.9");
        verify(limiter, never()).recordAttempt(anyString(), anyString());
    }
}