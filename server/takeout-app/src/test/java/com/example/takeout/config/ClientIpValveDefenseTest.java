package com.example.takeout.config;

import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.apache.catalina.valves.RemoteIpValve;
import org.junit.jupiter.api.Test;
import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import java.io.IOException;
import java.net.URI;
import static org.junit.jupiter.api.Assertions.assertEquals;

/** 实际启动临时 Tomcat 验证 remoteAddr；不加载业务、数据库和 Redis。 */
class ClientIpValveDefenseTest {
    @Test void nativeValveSeparatesTrustedClientsAndIgnoresForgedLeftPrefix() throws Exception {
        var factory = new TomcatServletWebServerFactory(0);
        factory.setProtocol("org.apache.coyote.http11.Http11Nio2Protocol");
        factory.setAddress(java.net.InetAddress.getLoopbackAddress());
        var valve = new RemoteIpValve();
        valve.setRemoteIpHeader("X-Forwarded-For");
        valve.setInternalProxies("127\\.0\\.0\\.1");
        factory.addEngineValves(valve);
        var server = factory.getWebServer(context -> {
            var registration = context.addServlet("client", new HttpServlet() {
                @Override protected void doGet(HttpServletRequest request, HttpServletResponse response) throws IOException {
                    response.getWriter().write(request.getRemoteAddr());
                }
            });
            registration.addMapping("/");
        });
        try {
            server.start();
            for (String address : new String[]{"192.0.2.10", "192.0.2.11"}) {
                var connection = (java.net.HttpURLConnection) URI.create("http://127.0.0.1:" + server.getPort() + "/")
                        .toURL().openConnection(java.net.Proxy.NO_PROXY);
                connection.setConnectTimeout(3000);
                connection.setReadTimeout(3000);
                connection.setRequestProperty("X-Forwarded-For", "198.51.100.99, " + address + ", 127.0.0.1");
                try (var stream = connection.getInputStream()) {
                    assertEquals(address, new String(stream.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8));
                } finally { connection.disconnect(); }
            }
        } finally { server.stop(); }
    }
}
