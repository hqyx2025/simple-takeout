package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import com.example.takeout.security.PasswordUtil;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class AuthEmailRecoveryTest {
    private final UserDao users = mock(UserDao.class);
    private final SmsCodeVerifier codes = mock(SmsCodeVerifier.class);
    private final AuthService auth = new AuthService(users, mock(JwtUtil.class), codes);
    private User user(long id, String account, String phone) {
        return new User(id, account, "", phone, "hash", 0, 1, 20, "now", "", "", "751848863@qq.com");
    }

    @Test
    void sharedMailboxResetsOnlyTheAccountMatchingItsPhone() {
        when(users.findByPhoneForUpdate("13900139000")).thenReturn(Optional.of(user(2, "second", "13900139000")));
        auth.resetPasswordByEmail("13900139000", "751848863@qq.com", "123456", "newpass123");
        verify(codes).consume("recovery:2:login:13900139000:751848863@qq.com", "123456");
        verify(users).updatePassword(eq(2L), argThat(hash -> PasswordUtil.matches("newpass123", hash)), anyString());
        verify(users, never()).updatePassword(eq(1L), anyString(), anyString());
    }

    @Test
    void unknownPhoneOrWrongMailboxCannotConsumeCodeOrUpdatePassword() {
        when(users.findByPhoneForUpdate("13800138000")).thenReturn(Optional.of(user(1, "first", "13800138000")));
        assertThrows(BizException.class, () -> auth.resetPasswordByEmail("13900139000", "751848863@qq.com", "123456", "newpass123"));
        BizException error = assertThrows(BizException.class, () -> auth.resetPasswordByEmail("13800138000", "wrong@qq.com", "123456", "newpass123"));
        assertEquals("手机号或邮箱不匹配", error.getMessage());
        assertThrows(BizException.class, () -> auth.resetPasswordByEmail("13700137000", "751848863@qq.com", "123456", "newpass123"));
        verifyNoInteractions(codes);
        verify(users, never()).updatePassword(anyLong(), anyString(), anyString());
    }

    @Test
    void wrongMailboxIsRejectedBeforeGeneratingOrSendingCode() {
        when(users.findByPhone("13800138000")).thenReturn(Optional.of(user(1, "first", "13800138000")));
        SmsVerificationService sender = mock(SmsVerificationService.class);
        var controller = new com.example.takeout.controller.AuthController(auth,
                mock(com.example.takeout.security.LoginRateLimiter.class),
                mock(com.example.takeout.security.TokenRevocationService.class),
                mock(RefreshTokenService.class), sender, mock(PushTokenService.class));
        var request = new com.example.takeout.controller.AuthController.EmailCodeRequest("13800138000", "wrong@qq.com", "login", null);
        BizException error = assertThrows(BizException.class, () -> controller.emailCode(request,
                mock(jakarta.servlet.http.HttpServletRequest.class)));
        assertEquals("手机号或邮箱不匹配", error.getMessage());
        verifyNoInteractions(sender);
    }

    @Test
    void accountAndPurposeHaveDifferentCodeIdentities() {
        User first = user(1, "first", "13800138000");
        assertNotEquals(auth.recoveryIdentity(first, "login"), auth.recoveryIdentity(first, "payment"));
        assertNotEquals(auth.recoveryIdentity(first, "login"), auth.recoveryIdentity(user(2, "second", "13900139000"), "login"));
        assertThrows(BizException.class, () -> auth.recoveryIdentity(first, "other"));
        when(users.findByPhoneForUpdate("13800138000")).thenReturn(Optional.of(first));
        auth.resetPaymentPasswordByEmail("13800138000", "751848863@qq.com", "123456", "654321");
        verify(codes).consume("recovery:1:payment:13800138000:751848863@qq.com", "123456");
        verify(users).updatePaymentPassword(eq(1L), anyString());
    }

    @Test
    void registrationAcceptsSharedEmailButRejectsDuplicateAccountOrPhone() {
        User stored = user(2, "second", "13900139000");
        when(users.insert(eq("second"), eq("13900139000"), eq("751848863@qq.com"), anyString(), eq(0), eq(0.0), anyString())).thenReturn(stored);
        assertEquals(2, auth.register("second", "13900139000", "751848863@qq.com", "123456", "newpass123", 0).id());
        verify(codes).consume("registration:13900139000:751848863@qq.com", "123456");
        when(users.existsByUsername("first")).thenReturn(true);
        assertThrows(BizException.class, () -> auth.register("first", "13900139000", "751848863@qq.com", "123456", "newpass123", 0));
        when(users.existsByPhone("13800138000")).thenReturn(true);
        assertThrows(BizException.class, () -> auth.register("third", "13800138000", "751848863@qq.com", "123456", "newpass123", 0));
    }

    @Test
    void missingOrWrongRegistrationCodeNeverCreatesAnAccount() {
        assertThrows(BizException.class, () -> auth.register("new", "13900139000", "user@example.com", null, "newpass123", 0));
        verifyNoInteractions(codes);
        doThrow(new BizException("验证码不正确或已过期")).when(codes)
                .consume("registration:13900139000:user@example.com", "123456");
        assertThrows(BizException.class, () -> auth.register("new", "13900139000", "user@example.com", "123456", "newpass123", 0));
        verify(users, never()).insert(anyString(), anyString(), anyString(), anyString(), anyInt(), anyDouble(), anyString());
    }

    @Test
    void registrationCodeRequestDoesNotRevealAccountExistence() {
        when(users.existsByUsername("existing")).thenReturn(true);
        SmsVerificationService sender = mock(SmsVerificationService.class);
        var controller = new com.example.takeout.controller.AuthController(auth,
                mock(com.example.takeout.security.LoginRateLimiter.class),
                mock(com.example.takeout.security.TokenRevocationService.class),
                mock(RefreshTokenService.class), sender, mock(PushTokenService.class));
        var request = new com.example.takeout.controller.AuthController.EmailCodeRequest(
                "13900139000", "user@example.com", "register", "existing");
        when(sender.issue("registration:13900139000:user@example.com", "user@example.com"))
                .thenReturn(new SmsVerificationService.IssueResult("", false));
        assertDoesNotThrow(() -> controller.emailCode(request, mock(jakarta.servlet.http.HttpServletRequest.class)));
        verify(sender).issue("registration:13900139000:user@example.com", "user@example.com");
        verify(users, never()).existsByUsername(anyString());
        verify(users, never()).existsByPhone(anyString());
    }
}
