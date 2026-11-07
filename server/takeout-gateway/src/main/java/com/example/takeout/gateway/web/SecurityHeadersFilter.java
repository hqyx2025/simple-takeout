package com.example.takeout.gateway.web;

import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

@Component
public class SecurityHeadersFilter implements WebFilter,
        org.springframework.context.ApplicationListener<org.springframework.boot.web.server.context.WebServerInitializedEvent> {
    private volatile int managementPort = -1;

    @Override
    public void onApplicationEvent(org.springframework.boot.web.server.context.WebServerInitializedEvent event) {
        if ("management".equals(event.getApplicationContext().getServerNamespace())) {
            managementPort = event.getWebServer().getPort();
        }
    }
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        var headers = exchange.getResponse().getHeaders();
        headers.set("X-Content-Type-Options", "nosniff");
        headers.set("X-Frame-Options", "DENY");
        headers.set("Referrer-Policy", "no-referrer");
        headers.set("Content-Security-Policy", "default-src 'self'; script-src 'self'; "
                + "style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; "
                + "connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'");
        String path=exchange.getRequest().getPath().value();
        var local = exchange.getRequest().getLocalAddress();
        boolean managementRequest = local != null && local.getPort() == managementPort;
        if(path.startsWith("/api/internal/") || path.startsWith("/internal/") || (path.startsWith("/actuator") && !managementRequest)){
            exchange.getResponse().setStatusCode(org.springframework.http.HttpStatus.NOT_FOUND);
            return exchange.getResponse().setComplete();
        }
        return chain.filter(exchange);
    }
}
