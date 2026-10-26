package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.security.JwtUtil;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StringRedisTemplate;
import com.example.takeout.security.LoginRateLimiter;
import org.springframework.mock.web.MockHttpServletRequest;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Replays the report's entry points without touching real users or balances. */
class AuditDefenseRegressionTest {
    @Test
    void publicRegistrationCannotCreatePrivilegedRoles() {
        for (int role : new int[]{1, 2, 3}) {
            UserDao users = mock(UserDao.class);
            SmsCodeVerifier codes = mock(SmsCodeVerifier.class);
            AuthService auth = new AuthService(users, mock(JwtUtil.class), codes);
            BizException error = assertThrows(BizException.class,
                    () -> auth.register("attacker", "13900000000", "test@example.com", "123456", "testpass", role));
            assertEquals(403, error.getCode());
            verifyNoInteractions(codes);
            verify(users, never()).insert(anyString(), anyString(), anyString(), anyString(), anyInt(), anyDouble(), anyString());
        }
    }

    @Test
    void unsafeDemoConfigurationCannotStartAuthService() {
        assertThrows(IllegalStateException.class, () -> new AuthService(
                mock(UserDao.class), mock(JwtUtil.class), mock(SmsCodeVerifier.class), true, 20));
        assertThrows(IllegalStateException.class, () -> new AuthService(
                mock(UserDao.class), mock(JwtUtil.class), mock(SmsCodeVerifier.class), false, 20));
        assertThrows(IllegalStateException.class, () -> new com.example.takeout.config.DemoModeWarning(true, false));
    }

    @Test
    void forwardingHeadersFromDirectClientsCannotSelectRateLimitBucket() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRemoteAddr("192.0.2.10");
        request.addHeader("X-Forwarded-For", "198.51.100.99");
        request.addHeader("X-Real-IP", "198.51.100.98");
        assertEquals("192.0.2.10", LoginRateLimiter.clientIp(request));
    }

    @Test
    @SuppressWarnings("unchecked")
    void redisOutageDoesNotDisableBruteForceProtection() {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        LoginRateLimiter limiter = new LoginRateLimiter(provider);
        for (int i = 0; i < 10; i++) limiter.recordAttempt("login", "192.0.2.10");
        assertTrue(limiter.isBlocked("login", "192.0.2.10"));
        assertFalse(limiter.isBlocked("login", "192.0.2.11"));
    }
}
