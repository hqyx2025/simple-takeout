package com.example.takeout.controller;

import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.security.TokenRevocationService;
import com.example.takeout.service.AuthService;
import com.example.takeout.service.RefreshTokenService;
import com.example.takeout.service.PushTokenService;
import com.example.takeout.service.SmsVerificationService;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class AuthPushTokenControllerTest {
    @Test
    void usesAuthenticatedAccountAndReturnsOnlyProfileId() throws Exception {
        PushTokenService tokens = mock(PushTokenService.class);
        when(tokens.profileId(7)).thenReturn("anonymous-profile");
        AuthController controller = new AuthController(mock(AuthService.class), mock(LoginRateLimiter.class),
                mock(TokenRevocationService.class), mock(RefreshTokenService.class),
                mock(SmsVerificationService.class), tokens);
        var mvc = MockMvcBuilders.standaloneSetup(controller).build();
        mvc.perform(post("/api/auth/push-token").requestAttr("userId", 7L)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":99,\"token\":\"secret-device-token\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.profileId").value("anonymous-profile"))
                .andExpect(jsonPath("$.data.token").doesNotExist());
        verify(tokens).register(7, "secret-device-token");
    }
}
