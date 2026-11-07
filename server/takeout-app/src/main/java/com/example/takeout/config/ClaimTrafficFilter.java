package com.example.takeout.config;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.common.DatabaseAvailability;
import com.example.takeout.security.AuthInterceptor;
import com.example.takeout.security.ClaimTrafficGuard;
import com.example.takeout.security.JwtUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.regex.Pattern;

/** 必须位于 MVC 认证之前，避免认证查库绕过流量准入。 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class ClaimTrafficFilter extends OncePerRequestFilter {
    private static final Pattern RIDER_GRAB = Pattern.compile("/api/rider/orders/([^/]+)/grab");
    private final ClaimTrafficGuard guard;
    private final JwtUtil jwt;
    private final ObjectMapper json;

    public ClaimTrafficFilter(ClaimTrafficGuard guard, JwtUtil jwt, ObjectMapper json) {
        this.guard = guard;
        this.jwt = jwt;
        this.json = json;
    }

    private String path(HttpServletRequest request) {
        String servletPath = request.getServletPath();
        return servletPath.isEmpty() ? request.getRequestURI().substring(request.getContextPath().length()) : servletPath;
    }

    @Override protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = path(request);
        return !"POST".equalsIgnoreCase(request.getMethod())
                || !("/api/coupons/claim".equals(path) || RIDER_GRAB.matcher(path).matches());
    }

    @Override protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        boolean rider = RIDER_GRAB.matcher(path(request)).matches();
        try (var lease = guard.enter(rider ? ClaimTrafficGuard.Action.RIDER : ClaimTrafficGuard.Action.COUPON)) {
            // 这里只做无数据库的签名/角色预检；原认证仍完整校验账号、吊销和四端权限。
            verifyToken(request, rider);
            String orderId = null;
            if (rider) {
                var match = RIDER_GRAB.matcher(path(request));
                if (match.matches()) {
                    try {
                        long id = Long.parseLong(match.group(1));
                        if (id <= 0) throw new NumberFormatException();
                        orderId = Long.toString(id);
                    } catch (NumberFormatException e) { throw new BizException(400, "订单编号不合法"); }
                }
            }
            lease.admit(orderId);
            try {
                chain.doFilter(request, response);
                if (request.getAttribute(DatabaseAvailability.FAILURE_ATTRIBUTE) != null) lease.failed();
                else lease.succeeded(request.getAttribute(AuthInterceptor.ATTR_USER_ID) != null);
            } catch (ServletException | IOException | RuntimeException e) {
                if (!DatabaseAvailability.unavailable(e)) throw e;
                lease.failed();
                if (response.isCommitted()) throw e;
                reject(response, new BizException(503, "服务暂时不可用，请稍后查询操作结果或重试"));
            }
        } catch (BizException e) { reject(response, e); }
    }

    private void verifyToken(HttpServletRequest request, boolean rider) {
        String header = request.getHeader("Authorization");
        if (header == null || !header.startsWith("Bearer ")) throw new BizException(401, "未登录或登录已过期");
        try {
            var claims = jwt.parseToken(header.substring(7));
            if (rider && jwt.getRole(claims) != 3) throw new BizException(403, "仅骑手可以执行该操作");
        } catch (BizException e) { throw e; }
        catch (RuntimeException e) { throw new BizException(401, "登录凭证无效或已过期"); }
    }

    private void reject(HttpServletResponse response, BizException error) throws IOException {
        response.setStatus(error.getCode());
        response.setHeader("Cache-Control", "no-store");
        if (error.getCode() == 429 || error.getCode() == 503 || error.getCode() == 409) response.setHeader("Retry-After", "1");
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        json.writeValue(response.getWriter(), ApiResponse.error(error.getCode(), error.getMessage()));
    }
}
