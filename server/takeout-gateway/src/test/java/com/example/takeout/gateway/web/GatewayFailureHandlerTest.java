package com.example.takeout.gateway.web;

import org.junit.jupiter.api.Test;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import static org.junit.jupiter.api.Assertions.*;

class GatewayFailureHandlerTest {
    @Test void failedDownstreamReturnsExplicitUnavailableWithoutFallback(){
        var exchange=MockServerWebExchange.from(MockServerHttpRequest.post("/api/erp/stores/10/receive"));
        new GatewayFailureHandler().handle(exchange,new java.net.ConnectException("refused")).block();
        assertEquals(503,exchange.getResponse().getStatusCode().value());
        String body=exchange.getResponse().getBodyAsString().block();assertTrue(body.contains("\"code\":503"));assertTrue(body.contains("原请求号"));
    }
    @Test void timeoutPreservesUncertainWriteOutcome(){
        var exchange=MockServerWebExchange.from(MockServerHttpRequest.post("/api/orders"));
        new GatewayFailureHandler().handle(exchange,new java.util.concurrent.TimeoutException()).block();
        assertEquals(504,exchange.getResponse().getStatusCode().value());
    }
    @Test void privateOperationsAreNotRoutedPublicly(){
        for(String path:new String[]{"/api/internal/erp/context","/internal/metrics","/actuator/env"}){
            var exchange=MockServerWebExchange.from(MockServerHttpRequest.get(path));
            new SecurityHeadersFilter().filter(exchange,e->{fail("private endpoint reached route");return reactor.core.publisher.Mono.empty();}).block();
            assertEquals(404,exchange.getResponse().getStatusCode().value());
        }
    }
}
