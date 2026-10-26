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
 * 登录限流接线测试：失败预算只计失败，总量与账号预算在验密前准入。
 */
class AuthControllerRateLimitTest {

    @org.junit.jupiter.api.BeforeEach void bindAccountIdentity() {
        AuthLoginStub.bind(authService, phone -> "account:" + phone);
    }

    @Test
    void loggingIntoOwnAccountCannotResetVictimGuessBudget() {
        var realLimiter = new LoginRateLimiter(mock(org.springframework.beans.factory.ObjectProvider.class));
        var guarded = new AuthController(authService, realLimiter, mock(TokenRevocationService.class),
                refreshTokenService, mock(com.example.takeout.service.SmsVerificationService.class),
                mock(com.example.takeout.service.PushTokenService.class));
        when(authService.login("13800138000", "123456", "USER")).thenThrow(new BizException("账号或密码错误"));
        var own = new AuthController.LoginRequest("13900000000", "own-password", "USER");
        when(authService.login(own.phone(), own.password(), own.loginType())).thenReturn(new AuthService.LoginResult(
                "token", new User(7, "own", "", own.phone(), "", 0, 0, "now")));
        for (int i = 0; i < 9; i++) assertThrows(BizException.class,
                () -> guarded.login(loginRequest, requestFrom("192.0.2.10")));
        guarded.login(own, requestFrom("192.0.2.10"));
        assertThrows(BizException.class, () -> guarded.login(loginRequest, requestFrom("192.0.2.10")));
        assertEquals(429, assertThrows(BizException.class,
                () -> guarded.login(loginRequest, requestFrom("192.0.2.10"))).getCode());
        verify(authService, org.mockito.Mockito.times(10)).login(loginRequest.phone(), loginRequest.password(), loginRequest.loginType());
    }

    private final AuthService authService = mock(AuthService.class);
    private final LoginRateLimiter limiter = mock(LoginRateLimiter.class);
    private final com.example.takeout.service.RefreshTokenService refreshTokenService =
            mock(com.example.takeout.service.RefreshTokenService.class);
    private final AuthController controller = new AuthController(authService, limiter,
            mock(TokenRevocationService.class), refreshTokenService,
            mock(com.example.takeout.service.SmsVerificationService.class),
            mock(com.example.takeout.service.PushTokenService.class));
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
    void successfulLoginConsumesOnlyTotalAndAccountBudgets() {
        User user = new User(1, "用户", "", "13800138000", "", 0, 20, "now");
        when(authService.login(anyString(), anyString(), anyString()))
                .thenReturn(new AuthService.LoginResult("token", user));
        when(refreshTokenService.issue(1, "token")).thenReturn("refresh-token");

        controller.login(loginRequest, requestFrom("9.9.9.9"));

        verify(limiter, never()).reset(anyString(), anyString());
        verify(limiter, never()).recordAttempt("login", "9.9.9.9");
        verify(limiter).recordAttempt("login-total", "9.9.9.9");
        verify(limiter).recordAttempt(org.mockito.ArgumentMatchers.eq("login-account-total"), anyString());
        verify(limiter, never()).recordAttempt(org.mockito.ArgumentMatchers.eq("login-account-fail"), anyString());
    }

    @Test
    void atomicAdmissionRejectionHappensBeforePasswordVerification() {
        org.mockito.Mockito.doThrow(new BizException(429, "limited")).when(limiter)
                .recordAttempt(org.mockito.ArgumentMatchers.eq("login-account-total"), anyString());
        assertEquals(429, assertThrows(BizException.class,
                () -> controller.login(loginRequest, requestFrom("192.0.2.10"))).getCode());
        verify(authService, never()).login(anyString(), anyString(), anyString());
    }

}
