package com.example.takeout.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;

/** No business requests or healthy load-balancer probes until every schema/data upgrade has completed. */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 7)
public class MigrationReadinessFilter extends OncePerRequestFilter {
    private volatile boolean ready;
    @EventListener(ApplicationReadyEvent.class)
    public void applicationReady() { ready = true; }

    @Override protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/") && !"/health".equals(request.getRequestURI());
    }

    @Override protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        if (ready) { chain.doFilter(request, response); return; }
        response.setStatus(503); response.setHeader("Retry-After", "2");
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write("{\"code\":503,\"message\":\"服务正在升级，请稍后重试\",\"data\":null}");
    }
}
