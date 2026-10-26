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
            var auth = mock(AuthInterceptor.class);
            when(auth.preHandle(any(), any(), any())).thenAnswer(call -> {
                jakarta.servlet.http.HttpServletRequest request = call.getArgument(0);
                if (!(request.getAttribute("userId") instanceof Long)) throw new BizException(401, "test requires auth");
                return true;
            }); return auth;
        }
        @Bean WebConfig web(AuthInterceptor auth, ObjectProvider<FileStorageService> storage, LoginRateLimiter limiter) {
            return new WebConfig(auth, new ApiRequestLoggingInterceptor(), storage, limiter);
        }
        @Bean StoreService stores() {
            var service = mock(StoreService.class);
            when(service.listStores(any(), any(), any())).thenReturn(List.of()); return service;
        }
        @Bean StoreController controller(StoreService stores) { return new StoreController(stores); }
    }
    private AnnotationConfigWebApplicationContext context; private MockMvc mvc;
    @BeforeEach void start() {
        context = new AnnotationConfigWebApplicationContext(); context.setServletContext(new MockServletContext());
        context.register(Config.class); context.refresh(); mvc = MockMvcBuilders.webAppContextSetup(context).build();
    }
    @AfterEach void stop() { context.close(); }

    @Test void allBrowseRoutesShare120RequestsPerAccountAndAuthenticationRunsFirst() throws Exception {
        mvc.perform(get("/api/stores")).andExpect(status().isUnauthorized());
        String[] routes = {"/api/stores", "/api/stores/recommended", "/api/rankings/stores", "/api/rankings/goods",
                "/api/goods/special", "/api/seckills", "/api/categories"};
        for (int i = 0; i < 120; i++) mvc.perform(get(routes[i % routes.length]).requestAttr("userId", 7L)).andExpect(status().isOk());
        mvc.perform(get("/api/stores").requestAttr("userId", 7L)).andExpect(status().isTooManyRequests());
        mvc.perform(get("/api/stores").requestAttr("userId", 8L)).andExpect(status().isOk());
        System.out.println("[RT-34/browse] shared-account=120 next=429 other-account=200 anonymous=401");
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
