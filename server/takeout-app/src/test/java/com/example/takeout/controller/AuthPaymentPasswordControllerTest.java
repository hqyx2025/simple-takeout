package com.example.takeout.controller;

import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.security.TokenRevocationService;
import com.example.takeout.service.AuthService;
import com.example.takeout.service.thirdparty.SmsSender;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class AuthPaymentPasswordControllerTest {
    @Test
    void setUsesAuthenticatedAccountAndReturnsNoSecrets() throws Exception {
        AuthService service = mock(AuthService.class);
        var limiter = mock(LoginRateLimiter.class);
        var controller = new AuthController(service, limiter, mock(TokenRevocationService.class), mock(SmsSender.class));
        var mvc = MockMvcBuilders.standaloneSetup(controller).build();
        mvc.perform(post("/api/auth/payment-password").requestAttr("userId", 7L)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":99,\"loginPassword\":\"login-secret\",\"paymentPassword\":\"135790\"}"))
                .andExpect(status().isOk()).andExpect(content().json("{\"code\":200,\"message\":\"success\",\"data\":null}"));
        verify(service).setPaymentPassword(7, "login-secret", "135790");
        verify(limiter).reset("payment-password", "7:127.0.0.1");
    }

    @Test
    void malformedPasswordBodyHasFixedMessage() throws Exception {
        var service = mock(AuthService.class);
        var controller = new AuthController(service, mock(LoginRateLimiter.class),
                mock(TokenRevocationService.class), mock(SmsSender.class));
        var mvc = MockMvcBuilders.standaloneSetup(controller).build();
        mvc.perform(post("/api/auth/payment-password").requestAttr("userId", 7L)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"paymentPassword\":[\"135790\"]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value("请求参数格式不正确"));
        verifyNoInteractions(service);
    }
}
