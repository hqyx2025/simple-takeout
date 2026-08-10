package com.example.takeout.security;

import com.example.takeout.common.BizException;
import io.jsonwebtoken.Claims;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * 认证拦截器：校验 Authorization: Bearer <token>，
 * 解析后的 userId/role 写入 request attribute 供 Controller 使用
 */
@Component
public class AuthInterceptor implements HandlerInterceptor {

    public static final String ATTR_USER_ID = "userId";
    public static final String ATTR_ROLE = "role";

    private final JwtUtil jwtUtil;

    public AuthInterceptor(JwtUtil jwtUtil) {
        this.jwtUtil = jwtUtil;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        // 放行预检请求
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            return true;
        }
        String auth = request.getHeader("Authorization");
        if (auth == null || !auth.startsWith("Bearer ")) {
            throw new BizException(401, "未登录或登录已过期");
        }
        try {
            Claims claims = jwtUtil.parseToken(auth.substring(7));
            request.setAttribute(ATTR_USER_ID, jwtUtil.getUserId(claims));
            request.setAttribute(ATTR_ROLE, jwtUtil.getRole(claims));
            return true;
        } catch (Exception e) {
            throw new BizException(401, "登录凭证无效或已过期");
        }
    }
}
