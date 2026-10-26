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

class RoundTwoLoginDefenseTest {
    @Test void invisiblePhoneVariantsNeverReachCredentialLookup() {
        var users = mock(UserDao.class);
        var auth = new AuthService(users, mock(JwtUtil.class));
        for (char ignored : new char[]{0x200b, 0xad, 0x200c, 0x200d, 0x2060, 0xfeff, 0}) {
            for (int position = 0; position <= 11; position++) {
                String phone = "13800138000";
                String variant = phone.substring(0, position) + ignored + phone.substring(position);
                assertThrows(BizException.class, () -> auth.login(variant, "wrong", "ADMIN"));
            }
        }
        verifyNoInteractions(users);
    }

    @Test void ownSuccessfulLoginCannotResetSourceBudgetForOtherAccounts() {
        var auth = mock(AuthService.class);
        AuthLoginStub.bind(auth, phone -> "account:" + phone);
        var limiter = new LoginRateLimiter(mock(ObjectProvider.class));
        var controller = new AuthController(auth, limiter, mock(TokenRevocationService.class),
                mock(RefreshTokenService.class), mock(SmsVerificationService.class), mock(PushTokenService.class));
        var http = new MockHttpServletRequest();
        http.setRemoteAddr("192.0.2.10");
        when(auth.login(anyString(), eq("wrong"), anyString())).thenThrow(new BizException("账号或密码错误"));
        when(auth.login("13900000000", "own-password", "USER")).thenReturn(new AuthService.LoginResult(
                "token", new User(7, "own", "", "13900000000", "", 0, 0, "now")));
        for (int i = 0; i < 9; i++) {
            String phone = "1380013800" + i;
            assertThrows(BizException.class, () -> controller.login(new AuthController.LoginRequest(phone, "wrong", "USER"), http));
        }
        controller.login(new AuthController.LoginRequest("13900000000", "own-password", "USER"), http);
        assertEquals(400, assertThrows(BizException.class, () -> controller.login(
                new AuthController.LoginRequest("13800138009", "wrong", "ADMIN"), http)).getCode());
        assertEquals(429, assertThrows(BizException.class, () -> controller.login(
                new AuthController.LoginRequest("13800138009", "wrong", "ADMIN"), http)).getCode());
    }
}
