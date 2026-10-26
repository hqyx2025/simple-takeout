package com.example.takeout.config;

import com.example.takeout.common.GlobalExceptionHandler;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.context.annotation.*;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockServletContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.config.annotation.*;
import java.nio.file.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class Round3ResourceBoundaryTest {
    @TempDir static Path root;
    private AnnotationConfigWebApplicationContext context;
    private MockMvc mvc;
    private ch.qos.logback.classic.Logger logger;
    private ch.qos.logback.core.read.ListAppender<ch.qos.logback.classic.spi.ILoggingEvent> logs;

    @Configuration @EnableWebMvc static class Config implements WebMvcConfigurer {
        @Bean GlobalExceptionHandler errors() { return new GlobalExceptionHandler(); }
        @Bean Endpoint endpoint() { return new Endpoint(); }
        @Override public void addResourceHandlers(ResourceHandlerRegistry registry) {
            registry.addResourceHandler("/uploads/**").addResourceLocations(root.toUri().toString());
        }
    }
    @RestController static class Endpoint {
        @GetMapping("/status-404") void missing() { throw new ResponseStatusException(HttpStatus.NOT_FOUND, "private-detail"); }
        @GetMapping("/status-400") void malformed() { throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "private-detail"); }
        @GetMapping("/status-500") void internal() { throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "private-detail"); }
    }
    @BeforeEach void start() throws Exception {
        Files.createDirectories(root.resolve("empty"));
        context = new AnnotationConfigWebApplicationContext();
        context.setServletContext(new MockServletContext()); context.register(Config.class); context.refresh();
        mvc = MockMvcBuilders.webAppContextSetup(context).build();
        logger = (ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(GlobalExceptionHandler.class);
        logs = new ch.qos.logback.core.read.ListAppender<>(); logs.start(); logger.addAppender(logs);
    }
    @AfterEach void stop() { logger.detachAppender(logs); logs.stop(); context.close(); }

    @Test void missingRoutesAre404WithoutErrorStacks() throws Exception {
        mvc.perform(get("/not-mapped-anywhere")).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value(404));
        assertTrue(logs.list.isEmpty());
        System.out.println("[RT-20] NoHandlerFoundException -> 404 error-log=0");
    }
    @Test void typedMissingAndBadRequestsPreserveStatusWithoutLeakingReasons() throws Exception {
        for (int code : new int[]{400, 404}) mvc.perform(get("/status-" + code))
                .andExpect(status().is(code)).andExpect(jsonPath("$.code").value(code))
                .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("private-detail"))));
        assertTrue(logs.list.isEmpty());
        System.out.println("[RT-20] ResponseStatusException -> 400/404 error-log=0");
    }
    @Test void missingFileDirectoryAndEncodedTraversalShapesAre404() throws Exception {
        for (String path : new String[]{"/uploads", "/uploads/", "/uploads/missing.jpg", "/uploads/missing/",
                "/uploads/empty/", "/uploads/%2e%2e/private.txt"}) {
            mvc.perform(get(path)).andExpect(status().isNotFound());
        }
        assertTrue(logs.list.isEmpty());
        System.out.println("[RT-20] upload shapes=6 -> 404 error-log=0");
    }
    @Test void actualServerErrorsRemain500AndAreLogged() throws Exception {
        mvc.perform(get("/status-500")).andExpect(status().isInternalServerError())
                .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("private-detail"))));
        assertTrue(logs.list.stream().anyMatch(e -> e.getLevel() == ch.qos.logback.classic.Level.ERROR));
    }
    @Test void bothHttpsServersCoverSubdomainsWithoutClaimingPreloadEnrollment() throws Exception {
        String nginx = Files.readString(Path.of("../docker/nginx-domain.conf"));
        assertEquals(2, nginx.lines().filter(s -> s.contains("Strict-Transport-Security") && s.contains("includeSubDomains")).count());
        System.out.println("[RT-20] HTTPS server HSTS includeSubDomains count=2");
    }

    @Test void malformedPercentAndNulPathsAreRejectedByActualTomcatBeforeMvc() throws Exception {
        var factory = new org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory(0);
        factory.setAddress(java.net.InetAddress.getLoopbackAddress());
        factory.setProtocol("org.apache.coyote.http11.Http11Nio2Protocol");
        var server = factory.getWebServer(servletContext -> {
            var spring = new AnnotationConfigWebApplicationContext(); spring.register(Config.class);
            var registration = servletContext.addServlet("mvc", new org.springframework.web.servlet.DispatcherServlet(spring));
            registration.setLoadOnStartup(1); registration.addMapping("/");
        });
        try {
            server.start();
            for (String path : new String[]{"/uploads/%ZZ.jpg", "/uploads/%00.jpg"}) {
                try (var socket = new java.net.Socket("127.0.0.1", server.getPort())) {
                    socket.setSoTimeout(3000);
                    socket.getOutputStream().write(("GET " + path + " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
                            .getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                    var reader = new java.io.BufferedReader(new java.io.InputStreamReader(socket.getInputStream()));
                    assertTrue(reader.readLine().startsWith("HTTP/1.1 400"));
                }
            }
            assertTrue(logs.list.isEmpty());
            System.out.println("[RT-20] actual Tomcat malformed-percent/NUL -> 400 application-error-log=0");
        } finally { server.stop(); }
    }
}
