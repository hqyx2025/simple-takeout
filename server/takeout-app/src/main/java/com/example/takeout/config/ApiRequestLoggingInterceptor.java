package com.example.takeout.config;

import com.example.takeout.common.TraceContext;
import com.example.takeout.dao.OperationAuditLogDao;
import com.example.takeout.security.AuthInterceptor;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

import java.time.Instant;
import java.util.UUID;

/**
 * 统一记录前端访问后端 API 的请求、响应和耗时，便于真机联调定位数据问题。
 * 不记录 Authorization 和请求体，避免把登录凭证及用户隐私写入控制台。
 *
 * <p><b>traceId 贯穿</b>：优先沿用上游传入的 {@code X-Request-Id}（网关生成一次、
 * 下游各服务透传），没有才自行生成；同一值写入 MDC（供 logback pattern 打印）
 * 与响应头（供前端/抓包关联）。请求结束时必须清理 MDC——Servlet 线程池会复用线程，
 * 不清理会把上一个请求的 traceId 带到下一个请求的日志里。</p>
 */
@Component
public class ApiRequestLoggingInterceptor implements HandlerInterceptor {

    private static final Logger log = LoggerFactory.getLogger(ApiRequestLoggingInterceptor.class);
    private static final String START_TIME = ApiRequestLoggingInterceptor.class.getName() + ".startTime";
    private final OperationAuditLogDao operationLogDao;

    @Autowired
    public ApiRequestLoggingInterceptor(OperationAuditLogDao operationLogDao) {
        this.operationLogDao = operationLogDao;
    }

    ApiRequestLoggingInterceptor() {
        this.operationLogDao = null;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        request.setAttribute(START_TIME, System.nanoTime());
        String traceId = TraceContext.normalize(request.getHeader(TraceContext.HEADER));
        if (traceId == null) {
            traceId = UUID.randomUUID().toString().replace("-", "");
        }
        request.setAttribute(TraceContext.ATTR, traceId);
        TraceContext.bind(traceId);
        // 回写响应头：前端报错时可直接带上该值，服务端一次 grep 即可定位
        response.setHeader(TraceContext.HEADER, traceId);
        log.info("[接口请求开始] traceId={} method={} uri={} query={} client={} auth={}",
                traceId,
                request.getMethod(), request.getRequestURI(), query(request),
                request.getRemoteAddr(), hasBearerToken(request) ? "Bearer" : "None");
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response,
                                Object handler, Exception ex) {
        try {
            Object start = request.getAttribute(START_TIME);
            long durationMs = start instanceof Long
                    ? (System.nanoTime() - (Long) start) / 1_000_000
                    : -1;
            String traceId = String.valueOf(request.getAttribute(TraceContext.ATTR));
            Object userId = request.getAttribute(AuthInterceptor.ATTR_USER_ID);
            Object role = request.getAttribute(AuthInterceptor.ATTR_ROLE);
            String identity = userId == null ? "未登录" : "userId=" + userId + ", role=" + role;
            if (ex == null) {
                log.info("[接口请求结束] traceId={} {} method={} uri={} status={} durationMs={}",
                        traceId, identity, request.getMethod(), request.getRequestURI(), response.getStatus(), durationMs);
            } else {
                log.error("[接口请求异常] traceId={} {} method={} uri={} status={} durationMs={} error={}",
                        traceId, identity, request.getMethod(), request.getRequestURI(), response.getStatus(), durationMs,
                        ex.getMessage(), ex);
            }
            recordOperation(request, response, handler, userId, role, traceId);
        } finally {
            // 线程复用：必须清理，否则下一个请求的日志会带上本次的 traceId
            TraceContext.clear();
        }
    }

    private void recordOperation(HttpServletRequest request, HttpServletResponse response, Object handler,
                                 Object userId, Object role, String traceId) {
        if (operationLogDao == null || !(userId instanceof Number operatorId)
                || !(role instanceof Number operatorRole)
                || "GET".equalsIgnoreCase(request.getMethod())
                || "OPTIONS".equalsIgnoreCase(request.getMethod())) {
            return;
        }
        String path = request.getRequestURI();
        long orderId = extractOrderId(path);
        boolean adminMutation = operatorRole.intValue() == 2 && path.startsWith("/api/admin/");
        boolean merchantMutation = operatorRole.intValue() == 1 && path.startsWith("/api/merchant/");
        if (!adminMutation && !merchantMutation && orderId == 0) {
            return;
        }
        String action = handler instanceof HandlerMethod method
                ? method.getBeanType().getSimpleName() + "." + method.getMethod().getName()
                : path;
        if (path.length() > 255) {
            path = path.substring(0, 255);
        }
        try {
            int status = response.getStatus();
            int orderStatus = orderId == 0 ? -1 : operationLogDao.currentOrderStatus(orderId);
            operationLogDao.insert(operatorId.longValue(), operatorRole.intValue(), orderId, orderStatus,
                    action, request.getMethod(), path,
                    status < 400 ? "SUCCESS" : "FAILURE", status, traceId,
                    Instant.now().toEpochMilli());
        } catch (RuntimeException e) {
            log.warn("操作审计写入失败 traceId={} path={}", traceId, path, e);
        }
    }

    private long extractOrderId(String path) {
        String[] segments = path.split("/");
        for (int i = 0; i < segments.length - 1; i++) {
            if ("orders".equals(segments[i])) {
                try {
                    return Long.parseLong(segments[i + 1]);
                } catch (NumberFormatException ignored) {
                    return 0;
                }
            }
        }
        return 0;
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
