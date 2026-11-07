package com.example.takeout.gateway.web;

import com.example.takeout.common.TraceContext;
import org.junit.jupiter.api.Test;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import reactor.core.publisher.Mono;

import static org.junit.jupiter.api.Assertions.*;

class RequestTraceFilterTest {
    @Test void forwardsOneSafeIdAndOverridesDuplicateDownstreamResponseHeaders() {
        var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/orders")
                .header(TraceContext.HEADER, "upstream-42", "ignored"));
        new RequestTraceFilter().filter(exchange, traced -> {
            assertEquals(java.util.List.of("upstream-42"), traced.getRequest().getHeaders().get(TraceContext.HEADER));
            traced.getResponse().getHeaders().add(TraceContext.HEADER, "downstream");
            return traced.getResponse().setComplete();
        }).block();
        assertEquals(java.util.List.of("upstream-42"), exchange.getResponse().getHeaders().get(TraceContext.HEADER));
        assertEquals("", TraceContext.current(), "reactive filter must not write thread-local MDC");
    }

    @Test void generatesAnIdForFailureResponsesAndExposesItInReactorContext() {
        var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/orders"));
        assertThrows(IllegalStateException.class, () -> new RequestTraceFilter().filter(exchange, traced ->
                Mono.deferContextual(context -> {
                    assertEquals(traced.getResponse().getHeaders().getFirst(TraceContext.HEADER), context.get(TraceContext.MDC_KEY));
                    return Mono.error(new IllegalStateException("downstream unavailable"));
                })).block());
        assertTrue(exchange.getResponse().getHeaders().getFirst(TraceContext.HEADER).matches("[A-Za-z0-9]{32}"));
    }
}
