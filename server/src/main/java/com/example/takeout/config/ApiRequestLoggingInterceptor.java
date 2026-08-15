package com.example.takeout.config;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * 统一记录前端访问后端 API 的请求、响应和耗时，便于真机联调定位数据问题。
 * 不记录 Authorization 和请求体，避免把登录凭证及用户隐私写入控制台。
 */
@Component
public class ApiRequestLoggingInterceptor implements HandlerInterceptor {

    private static final Logger log = LoggerFactory.getLogger(ApiRequestLoggingInterceptor.class);
    private static final String START_TIME = ApiRequestLoggingInterceptor.class.getName() + ".startTime";

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        request.setAttribute(START_TIME, System.nanoTime());
        log.info("[API] 请求开始 method={} uri={} query={} client={} auth={}",
                request.getMethod(), request.getRequestURI(), query(request),
                request.getRemoteAddr(), hasBearerToken(request) ? "Bearer" : "None");
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response,
                                Object handler, Exception ex) {
        Object start = request.getAttribute(START_TIME);
        long durationMs = start instanceof Long
                ? (System.nanoTime() - (Long) start) / 1_000_000
                : -1;
        if (ex == null) {
            log.info("[API] 请求结束 method={} uri={} status={} durationMs={}",
                    request.getMethod(), request.getRequestURI(), response.getStatus(), durationMs);
        } else {
            log.error("[API] 请求异常 method={} uri={} status={} durationMs={} error={}",
                    request.getMethod(), request.getRequestURI(), response.getStatus(), durationMs,
                    ex.getMessage(), ex);
        }
    }

    private String query(HttpServletRequest request) {
        String query = request.getQueryString();
        return query == null || query.isBlank() ? "-" : query;
    }

    private boolean hasBearerToken(HttpServletRequest request) {
        String authorization = request.getHeader("Authorization");
        return authorization != null && authorization.startsWith("Bearer ");
    }
}
