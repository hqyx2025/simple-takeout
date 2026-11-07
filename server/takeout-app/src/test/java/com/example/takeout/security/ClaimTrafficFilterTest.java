package com.example.takeout.security;

import com.example.takeout.common.*;
import com.example.takeout.config.ClaimTrafficFilter;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.CannotGetJdbcConnectionException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class ClaimTrafficFilterTest {
    @RestController static class Endpoint {
        int calls;
        @PostMapping({"/api/coupons/claim", "/api/rider/orders/{id}/grab"}) String claim() { calls++; return "ok"; }
        @GetMapping("/api/other") String other() { return "ok"; }
    }

    @Test void databaseFailureDuringAuthenticationIs503AndLaterRequestsNeverReachAuthentication() throws Exception {
        AtomicLong clock = new AtomicLong(1_000_000_000L);
        var jdbc = mock(JdbcTemplate.class);
        var guard = new ClaimTrafficGuard(mock(ObjectProvider.class), jdbc, ClaimTrafficGuardTest.settings(4, 100, 1), clock::get);
        var jwt = mock(JwtUtil.class); var claims = mock(Claims.class);
        when(jwt.parseToken("valid")).thenReturn(claims);
        when(jwt.getUserId(claims)).thenReturn(7L);
        var users = mock(UserDao.class);
        when(users.findById(7)).thenThrow(new CannotGetJdbcConnectionException("private connection details"));
        var endpoint = new Endpoint();
        var mvc = MockMvcBuilders.standaloneSetup(endpoint).setControllerAdvice(new GlobalExceptionHandler())
                .addInterceptors(new AuthInterceptor(jwt, users, mock(TokenRevocationService.class)))
                .addFilters(new ClaimTrafficFilter(guard, jwt, new ObjectMapper())).build();
        for (int i = 0; i < 10; i++) mvc.perform(post("/api/coupons/claim").header("Authorization", "Bearer valid"))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value(503));
        verify(users, times(1)).findById(7);
        assertEquals(0, endpoint.calls);
        clock.addAndGet(java.time.Duration.ofSeconds(5).toNanos());
        when(jdbc.queryForObject("SELECT 1", Integer.class)).thenReturn(1);
        doReturn(Optional.of(new User(7, "user", "", "13800138000", "", 0, 0, "now"))).when(users).findById(7);
        mvc.perform(post("/api/coupons/claim").header("Authorization", "Bearer valid")).andExpect(status().isOk());
        assertEquals(1, endpoint.calls);
    }

    @Test void overloadPrecedesAuthenticationAndPathsHonorDeploymentContext() throws Exception {
        var jdbc = mock(JdbcTemplate.class);
        var guard = new ClaimTrafficGuard(mock(ObjectProvider.class), jdbc, ClaimTrafficGuardTest.settings(1, 100, 3));
        var jwt = mock(JwtUtil.class);
        var auth = mock(AuthInterceptor.class);
        var mvc = MockMvcBuilders.standaloneSetup(new Endpoint()).setControllerAdvice(new GlobalExceptionHandler())
                .addInterceptors(auth).addFilters(new ClaimTrafficFilter(guard, jwt, new ObjectMapper())).build();
        try (var held = guard.enter(ClaimTrafficGuard.Action.COUPON)) {
            mvc.perform(post("/takeout/api/coupons/claim").contextPath("/takeout"))
                    .andExpect(status().isServiceUnavailable()).andExpect(header().string("Retry-After", "1"));
            mvc.perform(post("/api/rider/orders/900/grab")).andExpect(status().isServiceUnavailable());
            verifyNoInteractions(auth, jwt, jdbc);
        }
    }

    @Test void invalidTokensAndWrongRolesDoNotTouchAuthenticationDatabase() throws Exception {
        var guard = new ClaimTrafficGuard(mock(ObjectProvider.class), mock(JdbcTemplate.class), ClaimTrafficGuardTest.settings(4, 100, 3));
        var jwt = mock(JwtUtil.class);
        when(jwt.parseToken(anyString())).thenThrow(new IllegalArgumentException("invalid"));
        var auth = mock(AuthInterceptor.class);
        var mvc = MockMvcBuilders.standaloneSetup(new Endpoint()).setControllerAdvice(new GlobalExceptionHandler())
                .addInterceptors(auth).addFilters(new ClaimTrafficFilter(guard, jwt, new ObjectMapper())).build();
        mvc.perform(post("/api/coupons/claim")).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/rider/orders/900/grab").header("Authorization", "Bearer invalid")).andExpect(status().isUnauthorized());
        doReturn(mock(Claims.class)).when(jwt).parseToken("customer");
        mvc.perform(post("/api/rider/orders/900/grab").header("Authorization", "Bearer customer")).andExpect(status().isForbidden());
        verifyNoInteractions(auth);
    }
}
