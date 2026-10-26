package com.example.takeout.service;

import com.example.takeout.dao.UserDao;
import com.example.takeout.common.BizException;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import com.example.takeout.security.PasswordUtil;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;

class AuthServiceSecurityTest {

    @Test
    void legacyPasswordLoginUpgradesHashWithoutChangingPasswordTimestamp() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        String legacyHash = "b86af4172288a2cd465eedefe52f92400e1ae6ad620609a340505ad63b4519cd";
        String passwordChangedAt = "2026-09-17 22:39:20";
        User user = new User(1, "用户", "", "13800138000", legacyHash,
                0, 20, "2026-09-14 16:21:10", passwordChangedAt);
        when(userDao.findByPhone("13800138000")).thenReturn(java.util.Optional.of(user));
        when(jwtUtil.generateToken(1, 0, passwordChangedAt)).thenReturn("token");

        AuthService.LoginResult result = new AuthService(userDao, jwtUtil).login("13800138000", "123456");

        assertEquals("token", result.token());
        verify(jwtUtil).generateToken(1, 0, passwordChangedAt);
        verify(userDao).upgradePasswordHash(org.mockito.ArgumentMatchers.eq(1L),
                org.mockito.ArgumentMatchers.eq(legacyHash),
                org.mockito.ArgumentMatchers.argThat(hash -> hash.length() <= 128
                        && PasswordUtil.matches("123456", hash)));
        org.mockito.Mockito.verify(userDao, org.mockito.Mockito.never()).updatePassword(
                org.mockito.ArgumentMatchers.anyLong(), org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void loginRejectsAccountWhenLoginTypeDoesNotMatchRole() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        User merchant = new User(2, "商户", "", "13600136000", PasswordUtil.hash("123456"), 1, 0, "now");
        when(userDao.findByPhone("13600136000")).thenReturn(java.util.Optional.of(merchant));

        com.example.takeout.common.BizException error = assertThrows(
                com.example.takeout.common.BizException.class,
                () -> new AuthService(userDao, jwtUtil).login("13600136000", "123456", "USER"));

        assertEquals(403, error.getCode());
        assertEquals("登录端与账号角色不匹配，请切换正确的登录端", error.getMessage());
    }

    @Test
    void loginAcceptsMatchingAdminLoginType() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        User admin = new User(3, "管理员", "", "13100131000", PasswordUtil.hash("123456"), 2, 0, "now");
        when(userDao.findByPhone("13100131000")).thenReturn(java.util.Optional.of(admin));
        when(jwtUtil.generateToken(3, 2, "")).thenReturn("token");

        AuthService.LoginResult result = new AuthService(userDao, jwtUtil)
                .login("13100131000", "123456", "ADMIN");

        assertEquals("token", result.token());
        assertEquals(2, result.user().role());
    }

    @Test
    void loginRejectsUnknownLoginType() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        User user = new User(1, "用户", "", "13800138000", PasswordUtil.hash("123456"), 0, 20, "now");
        when(userDao.findByPhone("13800138000")).thenReturn(java.util.Optional.of(user));

        com.example.takeout.common.BizException error = assertThrows(
                com.example.takeout.common.BizException.class,
                () -> new AuthService(userDao, jwtUtil).login("13800138000", "123456", "UNKNOWN"));

        assertEquals("登录端类型不合法，仅支持 USER、MERCHANT、ADMIN、RIDER", error.getMessage());
    }

    @Test
    void registrationResultDoesNotExposePasswordHash() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        User stored = new User(1, "用户", "", "13800138000", "hash-value", 0, 20, "now");
        when(userDao.existsByPhone("13800138000")).thenReturn(false);
        when(userDao.insert(org.mockito.ArgumentMatchers.eq("用户"), org.mockito.ArgumentMatchers.eq("13800138000"),
                org.mockito.ArgumentMatchers.eq("user@example.com"), org.mockito.ArgumentMatchers.anyString(), org.mockito.ArgumentMatchers.eq(0),
                org.mockito.ArgumentMatchers.eq(0.0), org.mockito.ArgumentMatchers.anyString())).thenReturn(stored);

        User response = new AuthService(userDao, jwtUtil, mock(SmsCodeVerifier.class))
                .register("用户", "13800138000", "user@example.com", "123456", "123456", 0)
                .safe();

        assertEquals("", response.password());
        assertTrue(response.username().equals("用户"));
    }

    @Test
    void productionSignupBalanceCanBeDisabled() {
        UserDao userDao = mock(UserDao.class);
        when(userDao.existsByPhone("13800138000")).thenReturn(false);
        User stored = new User(1, "用户", "", "13800138000", "hash-value", 0, 0.0, "now");
        when(userDao.insert(eq("用户"), eq("13800138000"), eq("user@example.com"), anyString(),
                eq(0), eq(0.0), anyString())).thenReturn(stored);

        User result = new AuthService(userDao, mock(JwtUtil.class), mock(SmsCodeVerifier.class), false, 0.0)
                .register("用户", "13800138000", "user@example.com", "123456", "123456", 0);

        assertEquals(0.0, result.balance());
        verify(userDao).insert(eq("用户"), eq("13800138000"), eq("user@example.com"), anyString(),
                eq(0), eq(0.0), anyString());
    }

    @Test
    void profileUpdateRejectsPhoneOwnedByAnotherAccount() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        when(userDao.existsByPhoneExceptUser("13900139000", 1)).thenReturn(true);

        com.example.takeout.common.BizException error = org.junit.jupiter.api.Assertions.assertThrows(
                com.example.takeout.common.BizException.class,
                () -> new AuthService(userDao, jwtUtil).updateProfile(1, "新昵称", "13900139000"));

        assertEquals("该手机号已被其他账号使用", error.getMessage());
    }

    @Test
    void profileContactChangeRequiresCurrentPasswordAndRevokesSessions() {
        UserDao userDao = mock(UserDao.class);
        User current = new User(1, "用户", "", "13800138000", PasswordUtil.hash("oldpass"),
                0, 1, 20, "now", "", "", "user@example.com");
        when(userDao.findById(1)).thenReturn(java.util.Optional.of(current));
        when(userDao.existsByPhoneExceptUser("13900139000", 1)).thenReturn(false);
        when(userDao.existsByUsernameExceptUser("新昵称", 1)).thenReturn(false);
        when(userDao.findById(1)).thenReturn(java.util.Optional.of(current));

        AuthService service = new AuthService(userDao, mock(JwtUtil.class), mock(SmsCodeVerifier.class));
        BizException missing = assertThrows(BizException.class,
                () -> service.updateProfile(1, "新昵称", "13900139000", "new@example.com", ""));
        assertEquals("修改手机号或邮箱需要验证当前密码", missing.getMessage());

        when(userDao.findById(1)).thenReturn(java.util.Optional.of(current));
        service.updateProfile(1, "新昵称", "13900139000", "new@example.com", "oldpass");
        verify(userDao).updatePassword(eq(1L), eq(current.password()), anyString());
    }
    @Test
    void rechargeNeverAddsBalance() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        BizException error = assertThrows(BizException.class,
                () -> new AuthService(userDao, jwtUtil).recharge(1, 5.0));
        assertEquals(403, error.getCode());
        verifyNoInteractions(userDao);
    }

    @Test
    void rechargeIsDisabledByDefault() {
        UserDao userDao = mock(UserDao.class);
        AuthService service = new AuthService(userDao, mock(JwtUtil.class));
        BizException error = assertThrows(BizException.class, () -> service.recharge(1, 5.0));
        assertEquals("演示充值已停用", error.getMessage());
        verifyNoInteractions(userDao);
    }

    @Test
    void rechargeRejectsInvalidAmount() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);

        com.example.takeout.common.BizException error = assertThrows(
                com.example.takeout.common.BizException.class,
                () -> new AuthService(userDao, jwtUtil).recharge(1, 0));

        assertEquals(403, error.getCode());
    }

    @Test
    void changePasswordRejectsWrongOldPassword() {
        UserDao userDao = mock(UserDao.class);
        User user = new User(1, "用户", "", "13800138000", PasswordUtil.hash("123456"), 0, 20, "now");
        when(userDao.findByIdForUpdate(1)).thenReturn(java.util.Optional.of(user));

        com.example.takeout.common.BizException error = assertThrows(
                com.example.takeout.common.BizException.class,
                () -> new AuthService(userDao, mock(JwtUtil.class)).changePassword(1, "wrong", "newpass123"));

        assertEquals("原密码不正确", error.getMessage());
        verify(userDao, org.mockito.Mockito.never())
                .updatePassword(org.mockito.ArgumentMatchers.anyLong(),
                        org.mockito.ArgumentMatchers.anyString(), org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void changePasswordRejectsShortNewPassword() {
        UserDao userDao = mock(UserDao.class);
        User user = new User(1, "用户", "", "13800138000", PasswordUtil.hash("123456"), 0, 20, "now");
        when(userDao.findByIdForUpdate(1)).thenReturn(java.util.Optional.of(user));

        com.example.takeout.common.BizException error = assertThrows(
                com.example.takeout.common.BizException.class,
                () -> new AuthService(userDao, mock(JwtUtil.class)).changePassword(1, "123456", "12345"));

        assertEquals("新密码长度至少 6 位", error.getMessage());
    }

    @Test
    void changePasswordRejectsSamePassword() {
        UserDao userDao = mock(UserDao.class);
        User user = new User(1, "用户", "", "13800138000", PasswordUtil.hash("123456"), 0, 20, "now");
        when(userDao.findByIdForUpdate(1)).thenReturn(java.util.Optional.of(user));

        com.example.takeout.common.BizException error = assertThrows(
                com.example.takeout.common.BizException.class,
                () -> new AuthService(userDao, mock(JwtUtil.class)).changePassword(1, "123456", "123456"));

        assertEquals("新密码不能与原密码相同", error.getMessage());
    }

    /** 改密必须同时写新哈希与改密时间：只改哈希无法让旧 token 失效。 */
    @Test
    void changePasswordWritesNewHashAndChangeTime() {
        UserDao userDao = mock(UserDao.class);
        User user = new User(1, "用户", "", "13800138000", PasswordUtil.hash("123456"), 0, 20, "now");
        when(userDao.findByIdForUpdate(1)).thenReturn(java.util.Optional.of(user));

        new AuthService(userDao, mock(JwtUtil.class)).changePassword(1, "123456", "newpass123");

        verify(userDao).updatePassword(org.mockito.ArgumentMatchers.eq(1L),
                org.mockito.ArgumentMatchers.argThat(hash -> PasswordUtil.matches("newpass123", hash)),
                org.mockito.ArgumentMatchers.matches("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}"));
    }

    /** 改密时间秒精度下也必须严格递增，避免同秒连续改密留下上一轮 token。 */
    @Test
    void changePasswordAdvancesExistingChangeTimestamp() {
        UserDao userDao = mock(UserDao.class);
        User user = new User(1, "用户", "", "13800138000", PasswordUtil.hash("123456"), 0, 20,
                "now", "2999-01-01 00:00:00");
        when(userDao.findByIdForUpdate(1)).thenReturn(java.util.Optional.of(user));

        new AuthService(userDao, mock(JwtUtil.class)).changePassword(1, "123456", "newpass123");

        verify(userDao).updatePassword(org.mockito.ArgumentMatchers.eq(1L),
                org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.eq("2999-01-01 00:00:01"));
    }

    @Test
    void emailPasswordResetAlsoAdvancesExistingChangeTimestamp() {
        UserDao userDao = mock(UserDao.class);
        User user = new User(1, "user", "", "13800138000", PasswordUtil.hash("123456"),
                0, 1, 20, "now", "2999-01-01 00:00:00", "", "751848863@qq.com");
        when(userDao.findByPhoneForUpdate("13800138000")).thenReturn(java.util.Optional.of(user));

        SmsCodeVerifier verifier = mock(SmsCodeVerifier.class);
        new AuthService(userDao, mock(JwtUtil.class), verifier)
                .resetPasswordByEmail("13800138000", "751848863@qq.com", "123456", "newpass123");

        verify(verifier).consume("recovery:1:login:13800138000:751848863@qq.com", "123456");
        verify(userDao).updatePassword(org.mockito.ArgumentMatchers.eq(1L),
                org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.eq("2999-01-01 00:00:01"));
    }

    @Test
    void changingPasswordWithinTheSameSecondAdvancesThePersistedVersion() {
        UserDao users = mock(UserDao.class);
        User user = new User(7, "user", "", "13800138000", PasswordUtil.hash("123456"),
                0, 20, "now", "2026-10-14 12:00:00");
        when(users.findByIdForUpdate(7)).thenReturn(java.util.Optional.of(user));
        java.time.Clock clock = java.time.Clock.fixed(java.time.Instant.parse("2026-10-14T04:00:00.900Z"),
                java.time.ZoneId.of("Asia/Shanghai"));

        new AuthService(users, mock(JwtUtil.class), mock(SmsCodeVerifier.class), clock)
                .changePassword(7, "123456", "newpass123");

        verify(users).updatePassword(org.mockito.ArgumentMatchers.eq(7L),
                org.mockito.ArgumentMatchers.anyString(), org.mockito.ArgumentMatchers.eq("2026-10-14 12:00:01"));
    }
}
