package com.example.takeout.gateway.web;

import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

@Component
public class SecurityHeadersFilter implements WebFilter {
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        var headers = exchange.getResponse().getHeaders();
        headers.set("X-Content-Type-Options", "nosniff");
        headers.set("X-Frame-Options", "DENY");
        headers.set("Referrer-Policy", "no-referrer");
        headers.set("Content-Security-Policy", "default-src 'self'; script-src 'self'; "
                + "style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; "
                + "connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'");
        return chain.filter(exchange);
    }
}
