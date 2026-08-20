package com.example.takeout.service;

import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import com.example.takeout.security.PasswordUtil;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AuthServiceSecurityTest {

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
        when(jwtUtil.generateToken(3, 2)).thenReturn("token");

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

        assertEquals("登录端类型不合法，仅支持 USER、MERCHANT、ADMIN", error.getMessage());
    }

    @Test
    void registrationResultDoesNotExposePasswordHash() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        User stored = new User(1, "用户", "", "13800138000", "hash-value", 0, 20, "now");
        when(userDao.existsByPhone("13800138000")).thenReturn(false);
        when(userDao.insert(org.mockito.ArgumentMatchers.eq("用户"), org.mockito.ArgumentMatchers.eq("13800138000"),
                org.mockito.ArgumentMatchers.anyString(), org.mockito.ArgumentMatchers.eq(0),
                org.mockito.ArgumentMatchers.eq(20.0), org.mockito.ArgumentMatchers.anyString())).thenReturn(stored);

        User response = new AuthService(userDao, jwtUtil)
                .register("用户", "13800138000", "123456", 0)
                .safe();

        assertEquals("", response.password());
        assertTrue(response.username().equals("用户"));
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
    void rechargeAddsBalanceAndReturnsFreshUser() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);
        User before = new User(1, "鐢ㄦ埛", "", "13800138000", "", 0, 20.0, "now");
        User after = new User(1, "鐢ㄦ埛", "", "13800138000", "", 0, 25.0, "now");
        when(userDao.findById(1)).thenReturn(java.util.Optional.of(before), java.util.Optional.of(after));

        User result = new AuthService(userDao, jwtUtil).recharge(1, 5.0);

        verify(userDao).addBalance(1, 5.0);
        assertEquals(25.0, result.balance());
    }

    @Test
    void rechargeRejectsInvalidAmount() {
        UserDao userDao = mock(UserDao.class);
        JwtUtil jwtUtil = mock(JwtUtil.class);

        com.example.takeout.common.BizException error = assertThrows(
                com.example.takeout.common.BizException.class,
                () -> new AuthService(userDao, jwtUtil).recharge(1, 0));

        assertEquals("Recharge amount must be between 0.01 and 10000", error.getMessage());
    }
}
