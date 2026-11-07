package com.example.takeout.gateway.web;

import com.example.takeout.gateway.GatewayApplication;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.Test;
import org.springframework.boot.builder.SpringApplicationBuilder;

import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

class GatewayObservabilityTest {
    @Test void actualGatewayForwardsTraceButKeepsMetricsOffItsBusinessListener() throws Exception {
        var received = new AtomicReference<String>();
        var downstream = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        downstream.createContext("/api/trace-check", request -> {
            received.set(request.getRequestHeaders().getFirst("X-Request-Id"));
            request.getResponseHeaders().set("X-Request-Id", "downstream-other");
            byte[] body = "{\"code\":200}".getBytes(StandardCharsets.UTF_8);
            request.sendResponseHeaders(200, body.length);
            try (var output = request.getResponseBody()) { output.write(body); }
        });
        downstream.start();
        try (var context = new SpringApplicationBuilder(GatewayApplication.class).run("--server.port=0",
                "--server.address=127.0.0.1", "--management.server.port=0", "--management.server.address=127.0.0.1",
                "--takeout.test=true", "--TAKEOUT_APP_URI=http://127.0.0.1:" + downstream.getAddress().getPort())) {
            var env = context.getEnvironment();
            String base = "http://127.0.0.1:" + env.getRequiredProperty("local.server.port");
            String management = "http://127.0.0.1:" + env.getRequiredProperty("local.management.port");
            try (var client = HttpClient.newHttpClient()) {
                var response = client.send(HttpRequest.newBuilder(URI.create(base + "/api/trace-check"))
                        .header("X-Request-Id", "actual-request-42").GET().build(), HttpResponse.BodyHandlers.ofString());
                assertEquals(200, response.statusCode());
                assertEquals("actual-request-42", received.get());
                assertEquals(java.util.List.of("actual-request-42"), response.headers().allValues("X-Request-Id"));
                for (String path : new String[]{"/actuator/prometheus", "/internal/metrics", "/api/internal/erp/context"}) {
                    assertEquals(404, get(client, base + path).statusCode(), path);
                }
                var metrics = get(client, management + "/actuator/prometheus");
                assertEquals(200, metrics.statusCode());
                assertTrue(metrics.body().contains("jvm_memory_used_bytes"));
                assertEquals(404, get(client, management + "/actuator/env").statusCode());
            }
        } finally { downstream.stop(0); }
    }

    private HttpResponse<String> get(HttpClient client, String url) throws Exception {
        return client.send(HttpRequest.newBuilder(URI.create(url)).GET().build(), HttpResponse.BodyHandlers.ofString());
    }
}
