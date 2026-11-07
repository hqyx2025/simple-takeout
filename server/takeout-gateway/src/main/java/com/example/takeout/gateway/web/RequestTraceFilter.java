package com.example.takeout.gateway.web;

import com.example.takeout.common.TraceContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

/** Reactive work can change threads; keep its ID in the exchange/context, never thread-local MDC. */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 50)
public class RequestTraceFilter implements WebFilter {
    private static final Logger log = LoggerFactory.getLogger(RequestTraceFilter.class);

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String trace = TraceContext.resolve(exchange.getRequest().getHeaders().getFirst(TraceContext.HEADER));
        var traced = exchange.mutate().request(request -> request.headers(headers -> headers.set(TraceContext.HEADER, trace))).build();
        traced.getAttributes().put(TraceContext.ATTR, trace);
        traced.getResponse().getHeaders().set(TraceContext.HEADER, trace);
        traced.getResponse().beforeCommit(() -> {
            traced.getResponse().getHeaders().set(TraceContext.HEADER, trace);
            return Mono.empty();
        });
        long start = System.nanoTime();
        return Mono.defer(() -> chain.filter(traced)).doFinally(signal ->
                log.info("[Gateway] traceId={} method={} status={} durationMs={} outcome={}", trace,
                        traced.getRequest().getMethod(), traced.getResponse().getStatusCode(),
                        (System.nanoTime() - start) / 1_000_000, signal))
                .contextWrite(context -> context.put(TraceContext.MDC_KEY, trace));
    }
}
