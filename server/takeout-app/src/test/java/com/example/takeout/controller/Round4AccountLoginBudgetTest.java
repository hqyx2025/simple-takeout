package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.model.User;
import com.example.takeout.security.*;
import com.example.takeout.service.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.mock.web.MockHttpServletRequest;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round4AccountLoginBudgetTest {
    private final AuthService auth = mock(AuthService.class);
    private final LoginRateLimiter limiter = new LoginRateLimiter(mock(ObjectProvider.class));
    private final AuthController controller = new AuthController(auth, limiter, mock(TokenRevocationService.class),
            mock(RefreshTokenService.class), mock(SmsVerificationService.class), mock(PushTokenService.class));
    private final AuthController.LoginRequest good = new AuthController.LoginRequest("13800138000", "good", "USER");
    private final AuthController.LoginRequest bad = new AuthController.LoginRequest("13800138000", "bad", "USER");
    private void prepare() {
        AuthLoginStub.bind(auth, phone -> "u7");
        when(auth.login(good.phone(), good.password(), good.loginType())).thenReturn(new AuthService.LoginResult(
                "token", new User(7, "user", "", good.phone(), "", 0, 0, "now")));
        when(auth.login(bad.phone(), bad.password(), bad.loginType())).thenThrow(new BizException("账号或密码错误"));
    }
    private MockHttpServletRequest source(int suffix) {
        var request = new MockHttpServletRequest(); request.setRemoteAddr("192.0.2." + suffix); return request;
    }
    @Test void sameAccountTwelveSuccessfulLoginsDoNotTriggerTenMinuteLock() {
        prepare();
        for (int i = 0; i < 12; i++) assertDoesNotThrow(() -> controller.login(good, source(230)));
        assertFalse(limiter.isBlocked("login-account-fail", "u7"));
        System.out.println("[RT-23] same-account successes=12 denied=0 account-failure-block=false");
    }
    @Test void thirtySuccessesUseOnlyShortTotalBudgetAndNeverFailureBudget() {
        prepare();
        for (int i = 0; i < 30; i++) assertDoesNotThrow(() -> controller.login(good, source(230)));
        assertEquals(429, assertThrows(BizException.class, () -> controller.login(good, source(230))).getCode());
        assertTrue(limiter.isBlocked("login-account-total", "u7"));
        assertFalse(limiter.isBlocked("login-account-fail", "u7"));
        verify(auth, times(30)).login(good.phone(), good.password(), good.loginType());
        System.out.println("[RT-23] same-account successes=30 request-31=429 total-block=true failure-block=false");
    }
    @Test void successfulLoginsNeverEraseDistributedFailures() {
        prepare();
        for (int i = 0; i < 9; i++) {
            var http = source(100 + i);
            assertEquals(400, assertThrows(BizException.class, () -> controller.login(bad, http)).getCode());
            assertDoesNotThrow(() -> controller.login(good, source(230)));
        }
        assertEquals(400, assertThrows(BizException.class, () -> controller.login(bad, source(120))).getCode());
        assertEquals(429, assertThrows(BizException.class, () -> controller.login(good, source(231))).getCode());
        assertTrue(limiter.isBlocked("login-account-fail", "u7"));
        assertFalse(limiter.isBlocked("login", "192.0.2.231"));
        System.out.println("[RT-23] distributed failures=10 interleaved-successes=9 account-failure-block=true");
    }
    @Test void correctPasswordButWrongRoleDoesNotBurnPasswordFailureBudget() {
        prepare();
        var wrongRole = new AuthController.LoginRequest(good.phone(), good.password(), "RIDER");
        when(auth.login(wrongRole.phone(), wrongRole.password(), wrongRole.loginType()))
                .thenThrow(new BizException(403, "登录端与账号角色不匹配，请切换正确的登录端"));
        for (int i = 0; i < 12; i++) assertEquals(403, assertThrows(BizException.class,
                () -> controller.login(wrongRole, source(230))).getCode());
        assertDoesNotThrow(() -> controller.login(good, source(230)));
        assertFalse(limiter.isBlocked("login-account-fail", "u7"));
        assertFalse(limiter.isBlocked("login", "192.0.2.230"));
        System.out.println("[RT-23] verified-password wrong-role requests=12 status=403 password-failure-budget-spent=0");
    }
    @Test void accountFailuresStillBlockBeforeAuthenticationWhenLocalTableIsFullAndRedisIsDown() {
        prepare();
        for (int i = 0; i < 10_000; i++) limiter.recordAttempt("order", "fill-" + i);
        for (int i = 0; i < 10; i++) assertEquals(400, assertThrows(BizException.class,
                () -> controller.login(bad, source(230))).getCode());
        assertEquals(429, assertThrows(BizException.class, () -> controller.login(good, source(231))).getCode());
        verify(auth, never()).login(good.phone(), good.password(), good.loginType());
        System.out.println("[RT-23] full local table=10000 Redis=down account failures=10 different-source=429 before-auth=true");
    }
}
