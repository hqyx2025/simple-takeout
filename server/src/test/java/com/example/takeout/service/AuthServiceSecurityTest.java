package com.example.takeout.service;

import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AuthServiceSecurityTest {

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
}
