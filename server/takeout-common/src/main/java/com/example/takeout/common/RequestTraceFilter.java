package com.example.takeout.common;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/** Covers authentication/admission failures too, before MVC interceptors run. */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 5)
public class RequestTraceFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String previous = TraceContext.current();
        String trace = TraceContext.resolve(request.getHeader(TraceContext.HEADER));
        request.setAttribute(TraceContext.ATTR, trace);
        response.setHeader(TraceContext.HEADER, trace);
        TraceContext.bind(trace);
        try {
            chain.doFilter(request, response);
        } finally {
            TraceContext.clear();
            TraceContext.bind(previous);
        }
    }
}
