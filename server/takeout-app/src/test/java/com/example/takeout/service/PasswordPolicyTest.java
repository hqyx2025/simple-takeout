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

class PasswordPolicyTest {
    @Test void newPasswordsAcceptTheDocumentedAlphabetAndRejectOtherCharacters() {
        for (String value : new String[]{"123456", "abcdef", "Abc123", "Abc123!", "!@#$%^&*._+-=?", "a".repeat(64)}) {
            assertDoesNotThrow(() -> AuthService.requireNewPassword(value));
        }
        for (String value : new String[]{"short", "a".repeat(65), "Abc123'", "Abc123\"", "Abc123`", "Abc123\\",
                "Abc123;", "Abc123 ", "Abc123\n", "Abc123\0", "Abc123<script>", "Abc123中文", "Abc123🙂"}) {
            assertThrows(BizException.class, () -> AuthService.requireNewPassword(value));
        }
        assertThrows(BizException.class, () -> AuthService.requireNewPassword(null));
    }

    @Test void registrationAndRecoveryRejectInvalidPasswordBeforeConsumingAnEmailCode() {
        UserDao users = mock(UserDao.class);
        SmsCodeVerifier codes = mock(SmsCodeVerifier.class);
        AuthService auth = new AuthService(users, mock(JwtUtil.class), codes);
        assertThrows(BizException.class, () -> auth.register("new-user", "13800138000", "test@example.com", "123456", "Abc123';--", 0));
        assertThrows(BizException.class, () -> auth.resetPasswordByEmail("13800138000", "test@example.com", "123456", "Abc123<script>"));
        verifyNoInteractions(codes);
        verify(users, never()).insert(anyString(), anyString(), anyString(), anyString(), anyInt(), anyDouble(), anyString());
        verify(users, never()).updatePassword(anyLong(), anyString(), anyString());
    }

    @Test void existingPasswordsWithOtherSymbolsCanStillLogIn() {
        UserDao users = mock(UserDao.class);
        JwtUtil jwt = mock(JwtUtil.class);
        User user = new User(1, "existing", "", "13800138000", PasswordUtil.hash("Old'password;123"), 0, 0, "now");
        when(users.findByPhone(user.phone())).thenReturn(Optional.of(user));
        when(jwt.generateToken(eq(1L), eq(0), anyString())).thenReturn("access");
        assertEquals("access", new AuthService(users, jwt).login(user.phone(), "Old'password;123", "USER").token());
    }
}
