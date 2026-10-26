package com.example.takeout.config;

import com.example.takeout.security.AuthInterceptor;
import com.example.takeout.service.FileStorageService;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.*;
import org.springframework.mock.web.MockServletContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class WebBoundaryDefenseTest {
    private AnnotationConfigWebApplicationContext context;
    private MockMvc mvc;

    @Configuration @EnableWebMvc static class Config {
        @Bean com.example.takeout.common.GlobalExceptionHandler errors() {
            return new com.example.takeout.common.GlobalExceptionHandler();
        }
        @Bean FileStorageService storage() throws java.io.IOException {
            var storage = mock(FileStorageService.class);
            when(storage.root()).thenReturn(java.nio.file.Files.createTempDirectory("takeout-missing-resource"));
            return storage;
        }
        @Bean AuthInterceptor auth() {
            var auth = mock(AuthInterceptor.class);
            when(auth.preHandle(any(), any(), any())).thenReturn(true);
            return auth;
        }
        @Bean WebConfig web(AuthInterceptor auth, ObjectProvider<FileStorageService> storage) {
            return new WebConfig(auth, new ApiRequestLoggingInterceptor(), storage,
                    new com.example.takeout.security.LoginRateLimiter(mock(ObjectProvider.class)));
        }
        @Bean Endpoint endpoint() { return new Endpoint(); }
    }
    @RestController static class Endpoint {
        @GetMapping("/api/boundary-test") String get() { return "ok"; }
        @GetMapping("/api/location/limit-test") String location() { return "map"; }
    }
    @BeforeEach void start() {
        context = new AnnotationConfigWebApplicationContext();
        context.setServletContext(new MockServletContext());
        context.register(Config.class);
        context.refresh();
        mvc = MockMvcBuilders.webAppContextSetup(context).addFilters(new SecurityHeadersFilter()).build();
    }
    @AfterEach void stop() { context.close(); }

    @Test void untrustedOriginIsRejectedByActualMvcCorsHandling() throws Exception {
        mvc.perform(options("/api/boundary-test").header("Origin", "https://evil.example")
                        .header("Access-Control-Request-Method", "GET"))
                .andExpect(status().isForbidden())
                .andExpect(header().doesNotExist("Access-Control-Allow-Origin"))
                .andExpect(header().string("X-Content-Type-Options", "nosniff"));
    }
    @Test void businessOriginPreflightIsAllowedWithoutWildcard() throws Exception {
        mvc.perform(options("/api/boundary-test").header("Origin", "https://hqyx.website")
                        .header("Access-Control-Request-Method", "GET"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "https://hqyx.website"));
    }
    @Test void apiResponsesKeepTheExpectedSecurityAndCacheHeaders() throws Exception {
        mvc.perform(get("/api/boundary-test"))
                .andExpect(status().isOk()).andExpect(content().string("ok"))
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(header().string("X-Frame-Options", "DENY"))
                .andExpect(header().string("Referrer-Policy", "no-referrer"));
    }

    @Test void missingUploadsReturn404WithoutLoggingErrorStacks() throws Exception {
        var logger = (ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(
                com.example.takeout.common.GlobalExceptionHandler.class);
        var entries = new ch.qos.logback.core.read.ListAppender<ch.qos.logback.classic.spi.ILoggingEvent>();
        entries.start();
        logger.addAppender(entries);
        try {
            for (int i = 0; i < 5; i++) mvc.perform(get("/uploads/missing-" + i + ".jpg"))
                    .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value(404));
            org.junit.jupiter.api.Assertions.assertTrue(entries.list.isEmpty());
        } finally {
            logger.detachAppender(entries);
            entries.stop();
        }
    }

    @Test void allMapRequestsShareAccountBudgetBeforeTheUpstreamHandler() throws Exception {
        for (int i = 0; i < 30; i++) mvc.perform(get("/api/location/limit-test").requestAttr("userId", 7L))
                .andExpect(status().isOk());
        mvc.perform(get("/api/location/limit-test").requestAttr("userId", 7L))
                .andExpect(status().isTooManyRequests());
        mvc.perform(get("/api/location/limit-test").requestAttr("userId", 8L)).andExpect(status().isOk());
    }
}
