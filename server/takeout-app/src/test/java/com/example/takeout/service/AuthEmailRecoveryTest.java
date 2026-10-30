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
    void rejectedRegistrationDoesNotSpendTheEmailCodeAndCanRetryWithAnotherName() {
        when(users.existsByUsername("taken")).thenReturn(true);
        assertThrows(BizException.class, () -> auth.register("taken", "13900139000", "user@example.com", "123456", "newpass123", 0));
        verify(codes, never()).consume(anyString(), anyString());
        when(users.insert(eq("available"), eq("13900139000"), eq("user@example.com"), anyString(), eq(0), eq(0.0), anyString()))
                .thenReturn(user(2, "available", "13900139000"));
        assertEquals(2, auth.register("available", "13900139000", "user@example.com", "123456", "newpass123", 0).id());
        verify(codes).consume("registration:13900139000:user@example.com", "123456");
    }

    @Test
    void failedAccountInsertDoesNotSpendTheEmailCode() {
        when(users.insert(anyString(), anyString(), anyString(), anyString(), anyInt(), anyDouble(), anyString()))
                .thenThrow(new org.springframework.dao.DuplicateKeyException("concurrent signup"));
        assertThrows(BizException.class, () -> auth.register("new", "13900139000", "user@example.com", "123456", "newpass123", 0));
        verify(codes, never()).consume(anyString(), anyString());
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
        verify(sender, never()).issue(anyString(), anyString());
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
                .verify("registration:13900139000:user@example.com", "123456");
        assertThrows(BizException.class, () -> auth.register("new", "13900139000", "user@example.com", "123456", "newpass123", 0));
        verifyNoInteractions(users);
        verify(users, never()).insert(anyString(), anyString(), anyString(), anyString(), anyInt(), anyDouble(), anyString());
    }

    @Test
    void emailLoginUsesItsOwnCodeAndEnforcesRoleAndMailbox() {
        User account = user(1, "first", "13800138000");
        when(users.findByPhoneForUpdate(account.phone())).thenReturn(Optional.of(account));
        assertEquals(account.id(), auth.loginByEmailCode(account.phone(), "751848863@qq.com", "123456", "CUSTOMER", key -> {}).user().id());
        verify(codes).consume("recovery:1:signin:13800138000:751848863@qq.com", "123456");
        clearInvocations(codes);
        assertEquals(403, assertThrows(BizException.class, () -> auth.loginByEmailCode(
                account.phone(), account.email(), "123456", "ADMIN", key -> {})).getCode());
        verify(codes, never()).consume(anyString(), anyString());
        clearInvocations(codes);
        assertThrows(BizException.class, () -> auth.loginByEmailCode(account.phone(), "wrong@example.com", "123456", "CUSTOMER", key -> {}));
        verifyNoInteractions(codes);
    }

    @Test
    void captchaFailurePreventsSendingAnyEmailCode() {
        SmsVerificationService sender = mock(SmsVerificationService.class);
        doThrow(new BizException("校对码不正确或已过期")).when(sender).consumeCaptcha(any(), any(), any());
        var controller = new com.example.takeout.controller.AuthController(auth,
                mock(com.example.takeout.security.LoginRateLimiter.class),
                mock(com.example.takeout.security.TokenRevocationService.class), mock(RefreshTokenService.class),
                sender, mock(PushTokenService.class));
        var req = new com.example.takeout.controller.AuthController.EmailCodeRequest(
                "13800138000", "test@example.com", "signin", "", "invalid-id", "WRONG");
        assertThrows(BizException.class, () -> controller.emailCode(req, mock(jakarta.servlet.http.HttpServletRequest.class)));
        verify(sender, never()).issue(anyString(), anyString());
        verifyNoInteractions(users);
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
