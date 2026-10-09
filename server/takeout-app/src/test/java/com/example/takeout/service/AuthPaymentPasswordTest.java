package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import com.example.takeout.security.PasswordUtil;
import com.example.takeout.security.PaymentPasswordUtil;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class AuthPaymentPasswordTest {
    private final UserDao users = mock(UserDao.class);
    private final AuthService auth = new AuthService(users, mock(JwtUtil.class));

    @Test
    void currentLoginPasswordIsRequiredAndPaymentPinIsSaltedIndependently() {
        when(users.findById(7)).thenReturn(Optional.of(user()));
        auth.setPaymentPassword(7, "login-secret", "135790");
        ArgumentCaptor<String> hash = ArgumentCaptor.forClass(String.class);
        verify(users).updatePaymentPassword(eq(7L), hash.capture());
        assertTrue(PaymentPasswordUtil.matches("135790", hash.getValue()));
        assertFalse(hash.getValue().contains("135790"));
        assertNotEquals(PasswordUtil.hash("135790"), hash.getValue());
        verify(users, never()).updatePassword(anyLong(), anyString(), anyString());
    }

    @Test
    void incorrectLoginPasswordAndInvalidPinCannotChangeAnything() {
        when(users.findById(7)).thenReturn(Optional.of(user()));
        assertEquals("登录密码不正确", assertThrows(BizException.class,
                () -> auth.setPaymentPassword(7, "wrong", "135790")).getMessage());
        for (String pin : new String[]{null, "", "12345", "1234567", "１２３４５６", "12a456"}) {
            assertEquals("支付密码必须为 6 位数字", assertThrows(BizException.class,
                    () -> auth.setPaymentPassword(7, "login-secret", pin)).getMessage());
        }
        verify(users, never()).updatePaymentPassword(anyLong(), anyString());
    }

    private User user() {
        return new User(7, "用户", "", "13800138000", PasswordUtil.hash("login-secret"), 0, 20, "now");
    }
}
