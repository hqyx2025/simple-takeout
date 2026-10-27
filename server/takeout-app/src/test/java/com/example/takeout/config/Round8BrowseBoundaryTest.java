package com.example.takeout.config;

import com.example.takeout.common.*;
import com.example.takeout.controller.StoreController;
import com.example.takeout.security.*;
import com.example.takeout.service.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.*;
import org.springframework.mock.web.MockServletContext;
import org.springframework.test.web.servlet.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class Round8BrowseBoundaryTest {
    @Configuration @EnableWebMvc static class Config {
        @Bean GlobalExceptionHandler errors() { return new GlobalExceptionHandler(); }
        @Bean LoginRateLimiter limiter() { return new LoginRateLimiter(mock(ObjectProvider.class)); }
        @Bean AuthInterceptor auth() {
            return new AuthInterceptor(mock(JwtUtil.class), mock(com.example.takeout.dao.UserDao.class),
                    mock(TokenRevocationService.class));
        }
        @Bean WebConfig web(AuthInterceptor auth, ObjectProvider<FileStorageService> storage, LoginRateLimiter limiter) {
            return new WebConfig(auth, new ApiRequestLoggingInterceptor(), storage, limiter);
        }
        @Bean StoreService stores() {
            var service = mock(StoreService.class);
            when(service.listStores(any(), any(), any())).thenReturn(List.of()); return service;
        }
        @Bean StoreController controller(StoreService stores) { return new StoreController(stores); }
        @Bean com.example.takeout.controller.LocationController locations() {
            return mock(com.example.takeout.controller.LocationController.class);
        }
    }
    private AnnotationConfigWebApplicationContext context; private MockMvc mvc;
    @BeforeEach void start() {
        context = new AnnotationConfigWebApplicationContext(); context.setServletContext(new MockServletContext());
        context.register(Config.class); context.refresh(); mvc = MockMvcBuilders.webAppContextSetup(context).build();
    }
    @AfterEach void stop() { context.close(); }

    @Test void allBrowseRoutesShare120RequestsPerAccountAndAllowAnonymousBrowsing() throws Exception {
        mvc.perform(get("/api/stores")).andExpect(status().isOk());
        String[] routes = {"/api/stores", "/api/stores/recommended", "/api/rankings/stores", "/api/rankings/goods",
                "/api/goods/special", "/api/seckills", "/api/categories"};
        for (int i = 0; i < 120; i++) mvc.perform(get(routes[i % routes.length]).requestAttr("userId", 7L)).andExpect(status().isOk());
        mvc.perform(get("/api/stores").requestAttr("userId", 7L)).andExpect(status().isTooManyRequests());
        mvc.perform(get("/api/stores").requestAttr("userId", 8L)).andExpect(status().isOk());
        System.out.println("[RT-34/browse] shared-account=120 next=429 other-account=200 anonymous=200");
    }

    @Test void anonymousBrowseSharesItsSourceBudgetWithoutTrustingForwardedHeaders() throws Exception {
        for (int i = 0; i < 120; i++) {
            mvc.perform(get(i % 2 == 0 ? "/api/stores" : "/api/categories")
                    .header("X-Forwarded-For", "192.0.2." + i)).andExpect(status().isOk());
        }
        mvc.perform(get("/api/stores")).andExpect(status().isTooManyRequests());
        mvc.perform(get("/api/stores").with(request -> { request.setRemoteAddr("192.0.2.200"); return request; }))
                .andExpect(status().isOk());
        mvc.perform(get("/api/merchant/stores")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/stores").header("Authorization", "Bearer invalid")).andExpect(status().isUnauthorized());
    }

    @Test void anonymousLocationReadsShareTheirSourceBudget() throws Exception {
        for (int i = 0; i < 30; i++) {
            mvc.perform(get("/api/location/search").param("keyword", "测试地点"))
                    .andExpect(status().isOk());
        }
        mvc.perform(get("/api/location/search").param("keyword", "测试地点"))
                .andExpect(status().isTooManyRequests());
    }

    @Test void storeListDoesNotProducePerStoreInfoLogs() throws Exception {
        var logger = (ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(StoreController.class);
        var entries = new ch.qos.logback.core.read.ListAppender<ch.qos.logback.classic.spi.ILoggingEvent>();
        entries.start(); logger.addAppender(entries);
        try {
            for (int i = 0; i < 3; i++) mvc.perform(get("/api/stores").requestAttr("userId", 7L)).andExpect(status().isOk());
            long info = entries.list.stream().filter(e -> e.getLevel().isGreaterOrEqual(ch.qos.logback.classic.Level.INFO)).count();
            System.out.println("[RT-35] store-list-requests=3 controller-info-or-higher=" + info);
            assertEquals(0, info);
        } finally { logger.detachAppender(entries); entries.stop(); }
    }
}
