package com.example.takeout.config;

import com.example.takeout.common.GlobalExceptionHandler;
import com.example.takeout.controller.AuthController;
import com.example.takeout.dao.UserDao;
import com.example.takeout.security.*;
import com.example.takeout.service.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.*;
import org.springframework.mock.web.MockServletContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class UsernameAvailabilityTest {
    @Configuration @EnableWebMvc static class Config {
        @Bean UserDao users() { return mock(UserDao.class); }
        @Bean LoginRateLimiter limiter() { return new LoginRateLimiter(mock(ObjectProvider.class)); }
        @Bean AuthInterceptor auth(UserDao users) {
            return new AuthInterceptor(mock(JwtUtil.class), users, mock(TokenRevocationService.class));
        }
        @Bean WebConfig web(AuthInterceptor auth, ObjectProvider<FileStorageService> storage, LoginRateLimiter limiter) {
            return new WebConfig(auth, new ApiRequestLoggingInterceptor(), storage, limiter);
        }
        @Bean AuthController controller(UserDao users, LoginRateLimiter limiter) {
            return new AuthController(new AuthService(users, mock(JwtUtil.class), mock(SmsCodeVerifier.class)), limiter,
                    mock(TokenRevocationService.class), mock(RefreshTokenService.class),
                    mock(SmsVerificationService.class), mock(PushTokenService.class));
        }
        @Bean GlobalExceptionHandler errors() { return new GlobalExceptionHandler(); }
    }
    private AnnotationConfigWebApplicationContext context;
    private MockMvc mvc;
    @BeforeEach void start() {
        context = new AnnotationConfigWebApplicationContext(); context.setServletContext(new MockServletContext());
        context.register(Config.class); context.refresh(); mvc = MockMvcBuilders.webAppContextSetup(context).build();
    }
    @AfterEach void close() { context.close(); }
    @Test void anonymousUsernameCheckUsesTheActualUniquenessQueryWithoutCheckingPhoneOrSendingMail() throws Exception {
        UserDao users = context.getBean(UserDao.class);
        when(users.existsByUsername("taken")).thenReturn(true);
        mvc.perform(get("/api/auth/username-availability").param("username", " taken "))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data").value(false));
        mvc.perform(get("/api/auth/username-availability").param("username", "available"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data").value(true));
        verify(users, never()).existsByPhone(anyString());
    }
    @Test void invalidNamesAreRejectedAndRepeatedLookupsAreBounded() throws Exception {
        mvc.perform(get("/api/auth/username-availability").param("username", " ")).andExpect(status().isBadRequest());
        mvc.perform(get("/api/auth/username-availability").param("username", "a".repeat(65))).andExpect(status().isBadRequest());
        for (int i=0;i<58;i++) mvc.perform(get("/api/auth/username-availability").param("username", "name"))
                .andExpect(status().isOk());
        mvc.perform(get("/api/auth/username-availability").param("username", "name")).andExpect(status().isTooManyRequests());
    }
}
