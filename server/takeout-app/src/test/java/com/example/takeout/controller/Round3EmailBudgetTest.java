package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.*;
import com.example.takeout.service.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.mock.web.MockHttpServletRequest;
import java.util.Optional;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round3EmailBudgetTest {
    private final UserDao users = mock(UserDao.class);
    private final LoginRateLimiter limiter = spy(new LoginRateLimiter(mock(ObjectProvider.class)));
    private final SmsVerificationService codes = mock(SmsVerificationService.class);
    private final AuthController controller = new AuthController(new AuthService(users, mock(JwtUtil.class)), limiter,
            mock(TokenRevocationService.class), mock(RefreshTokenService.class), codes, mock(PushTokenService.class));

    private MockHttpServletRequest source(String ip) {
        var request = new MockHttpServletRequest(); request.setRemoteAddr(ip); return request;
    }

    @Test void invalidRecoveryCannotSpendVictimPhoneDayBudget() {
        var user = new User(7, "victim", "", "13800138000", "", 0, 1, 0, "now", "", null, "owner@example.com");
        when(users.findByPhone(user.phone())).thenReturn(Optional.of(user));
        for (int i = 1; i <= 5; i++) {
            var http = source("192.0.2." + i);
            var request = new AuthController.EmailCodeRequest(user.phone(), "wrong@example.com", "login", "unused");
            assertEquals(400, assertThrows(BizException.class,
                    () -> controller.emailCode(request, http)).getCode());
        }
        verify(limiter, never()).recordAttempt(eq("email-code-phone"), anyString());
        when(codes.issue(anyString(), eq(user.email()))).thenReturn(new SmsVerificationService.IssueResult("", false));
        assertDoesNotThrow(() -> controller.emailCode(new AuthController.EmailCodeRequest(
                user.phone(), user.email(), "login", "unused"), source("198.51.100.10")));
        System.out.println("[RT-19] invalid-mail attempts=5 phone-budget-spent=0 valid-recovery=allowed");
    }

    @Test void validRegistrationFromAttackerSourceCannotLockOtherSourcesForTheDay() {
        when(codes.issue(anyString(), anyString())).thenReturn(new SmsVerificationService.IssueResult("", false));
        var request = new AuthController.EmailCodeRequest("13800138000", "mail@example.com", "register", "new-user");
        for (int i = 0; i < 5; i++) controller.emailCode(request, source("192.0.2.10"));
        assertDoesNotThrow(() -> controller.emailCode(request, source("198.51.100.10")));
        verify(codes, times(6)).issue(anyString(), anyString());
        System.out.println("[RT-19] attacker-source sends=5 different-source=allowed");
    }
}
