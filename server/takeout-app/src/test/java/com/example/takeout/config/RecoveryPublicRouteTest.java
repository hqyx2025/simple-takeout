package com.example.takeout.config;

import com.example.takeout.security.AuthInterceptor;
import com.example.takeout.service.FileStorageService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.handler.MappedInterceptor;
import org.springframework.web.util.ServletRequestPathUtils;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class RecoveryPublicRouteTest {
    static class Registry extends InterceptorRegistry {
        java.util.List<Object> interceptors() { return getInterceptors(); }
    }

    @Test
    @SuppressWarnings("unchecked")
    void emailCodeAndBothRecoveryEndpointsArePublicButProfileIsProtected() {
        AuthInterceptor auth = mock(AuthInterceptor.class);
        Registry registry = new Registry();
        new WebConfig(auth, mock(ApiRequestLoggingInterceptor.class), mock(ObjectProvider.class),
                mock(com.example.takeout.security.LoginRateLimiter.class)).addInterceptors(registry);
        MappedInterceptor mapped = registry.interceptors().stream().map(value -> (MappedInterceptor) value)
                .filter(value -> value.getInterceptor() == auth).findFirst().orElseThrow();
        for (String path : new String[]{"/api/auth/email-code", "/api/auth/password/forgot", "/api/auth/payment-password/forgot"}) {
            MockHttpServletRequest request = new MockHttpServletRequest("POST", path);
            ServletRequestPathUtils.parseAndCache(request);
            assertFalse(mapped.matches(request), path);
        }
        MockHttpServletRequest profile = new MockHttpServletRequest("GET", "/api/auth/me");
        ServletRequestPathUtils.parseAndCache(profile);
        assertTrue(mapped.matches(profile));
    }
}
