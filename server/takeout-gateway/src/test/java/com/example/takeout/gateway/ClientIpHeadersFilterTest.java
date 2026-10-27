package com.example.takeout.gateway;

import com.example.takeout.gateway.web.ClientIpHeadersFilter;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import java.net.InetSocketAddress;
import static org.junit.jupiter.api.Assertions.*;

class ClientIpHeadersFilterTest {
    private final ClientIpHeadersFilter filter = new ClientIpHeadersFilter("127\\.0\\.0\\.1");

    @Test void directBrowserOriginSurvivesInternalRoutingAndIgnoresForgedHeaders() {
        var request = MockServerHttpRequest.get("http://localhost:19087/api/auth/login")
                .remoteAddress(new InetSocketAddress("192.0.2.10", 1234))
                .header("X-Forwarded-Host", "attacker.invalid")
                .header("X-Forwarded-Proto", "https").header("X-Forwarded-Port", "443").build();
        var result = filter.filter(new HttpHeaders(), MockServerWebExchange.from(request));
        assertEquals("localhost:19087", result.getFirst("X-Forwarded-Host"));
        assertEquals("http", result.getFirst("X-Forwarded-Proto"));
        assertEquals("19087", result.getFirst("X-Forwarded-Port"));
    }

    @Test void trustedTlsProxyPreservesExternalOriginWithoutAppendingInternalOrigin() {
        var request = MockServerHttpRequest.get("http://localhost:8087/api/auth/login")
                .remoteAddress(new InetSocketAddress("127.0.0.1", 1234))
                .header("X-Forwarded-Host", "hqyx.website")
                .header("X-Forwarded-Proto", "https").header("X-Forwarded-Port", "443").build();
        var result = filter.filter(new HttpHeaders(), MockServerWebExchange.from(request));
        assertEquals("hqyx.website", result.getFirst("X-Forwarded-Host"));
        assertEquals("https", result.getFirst("X-Forwarded-Proto"));
        assertEquals("443", result.getFirst("X-Forwarded-Port"));
    }

    private String resolve(String peer, String xff) {
        var request = MockServerHttpRequest.get("http://localhost/api/auth/login")
                .remoteAddress(new InetSocketAddress(peer, 1234))
                .header("X-Forwarded-For", xff).header("Forwarded", "for=198.51.100.1").build();
        var result = filter.filter(request.getHeaders(), MockServerWebExchange.from(request));
        assertNull(result.getFirst("Forwarded"));
        return result.getFirst("X-Forwarded-For");
    }

    @Test void publicDirectClientsCannotForgeTheirBucket() {
        assertEquals("192.0.2.10", resolve("192.0.2.10", "198.51.100.99"));
        assertEquals("192.0.2.11", resolve("192.0.2.11", "198.51.100.99"));
    }

    @Test void trustedNginxPreservesDifferentRealClients() {
        assertEquals("192.0.2.10", resolve("127.0.0.1", "192.0.2.10"));
        assertEquals("192.0.2.11", resolve("127.0.0.1", "192.0.2.11"));
    }

    @Test void attackerPrefixCannotOverrideRightmostUntrustedHop() {
        assertEquals("192.0.2.10", resolve("127.0.0.1", "198.51.100.99, 192.0.2.10, 127.0.0.1"));
    }

    @Test void malformedHeadersAndWildcardTrustAreRejected() {
        assertThrows(org.springframework.web.server.ResponseStatusException.class,
                () -> resolve("127.0.0.1", "bad-host.example"));
        assertThrows(IllegalStateException.class, () -> new ClientIpHeadersFilter(".*"));
    }

    @Test void oversizedOrEmptyTrustedChainsCannotCollapseIntoProxyBuckets() {
        assertEquals("192.0.2.10", resolve("127.0.0.1", "127.0.0.1,".repeat(31) + "192.0.2.10"));
        for (String xff : new String[]{"", "127.0.0.1,".repeat(32) + "192.0.2.10", " ".repeat(2049), "bad,127.0.0.1"}) {
            assertEquals(400, assertThrows(org.springframework.web.server.ResponseStatusException.class,
                    () -> resolve("127.0.0.1", xff)).getStatusCode().value());
        }
    }
}
