package com.example.takeout.security;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import io.jsonwebtoken.Claims;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.util.AntPathMatcher;

import java.util.List;

/**
 * 认证拦截器：校验 Authorization: Bearer <token>，
 * 解析后的 userId/role 写入 request attribute 供 Controller 使用
 *
 * <p>这里同时是「登录态可吊销」的唯一收口：登出拉黑的 jti、以及改密后失效的旧 token
 * 都在本处拦下，任何接口都不会绕过。</p>
 */
@Component
public class AuthInterceptor implements HandlerInterceptor {

    public static final String ATTR_USER_ID = "userId";
    public static final String ATTR_ROLE = "role";
    public static final List<String> PUBLIC_BROWSE_PATHS = List.of(
            "/api/stores", "/api/stores/**", "/api/categories", "/api/search", "/api/goods/special",
            "/api/rankings/**", "/api/seckills", "/api/banners", "/api/announcements");
    private static final AntPathMatcher PATH_MATCHER = new AntPathMatcher();

    private final JwtUtil jwtUtil;
    private final UserDao userDao;
    private final TokenRevocationService tokenRevocationService;

    public AuthInterceptor(JwtUtil jwtUtil, UserDao userDao, TokenRevocationService tokenRevocationService) {
        this.jwtUtil = jwtUtil;
        this.userDao = userDao;
        this.tokenRevocationService = tokenRevocationService;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        // 放行预检请求
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            return true;
        }
        String auth = request.getHeader("Authorization");
        String path = request.getRequestURI();
        if (auth == null && "GET".equalsIgnoreCase(request.getMethod()) && path != null) {
            String applicationPath = path.substring(request.getContextPath().length());
            if (PUBLIC_BROWSE_PATHS.stream().anyMatch(pattern -> PATH_MATCHER.match(pattern, applicationPath))
                    || PATH_MATCHER.match("/api/location/**", applicationPath)) {
                return true;
            }
        }
        if (auth == null || !auth.startsWith("Bearer ")) {
            throw new BizException(401, "未登录或登录已过期");
        }
        try {
            Claims claims = jwtUtil.parseToken(auth.substring(7));
            if (tokenRevocationService.isRevoked(jwtUtil.getJti(claims))) {
                throw new BizException(401, "登录已退出，请重新登录");
            }
            long userId = jwtUtil.getUserId(claims);
            int tokenRole = jwtUtil.getRole(claims);
            User user = userDao.findById(userId)
                    .orElseThrow(() -> new BizException(401, "用户不存在，请重新登录"));
            if (user.role() != tokenRole) {
                throw new BizException(401, "登录身份已变化，请重新登录");
            }
            if (user.status() != 1) {
                throw new BizException(401, "账号已被禁用，请联系管理员");
            }
            // 改密即失效：两个时间同为 yyyy-MM-dd HH:mm:ss，字典序即时间序；
            // token 里的时间早于库里的改密时间，说明它签发于改密之前
            String changedAt = user.passwordChangedAt() == null ? "" : user.passwordChangedAt();
            if (!changedAt.isBlank() && changedAt.compareTo(jwtUtil.getPasswordChangedAt(claims)) > 0) {
                throw new BizException(401, "密码已修改，请重新登录");
            }
            String contextPath = request.getContextPath();
            String applicationPath = path == null ? "" : path.substring(contextPath == null ? 0 : contextPath.length());
            if (applicationPath.equals("/api/orders") || applicationPath.startsWith("/api/orders/")) {
                boolean merchantDetail = user.role() == 1 && "GET".equalsIgnoreCase(request.getMethod())
                        && applicationPath.matches("/api/orders/[0-9]+");
                if (user.role() != 0 && !merchantDetail) {
                    throw new BizException(403, "请使用用户账号操作个人订单");
                }
            }
            request.setAttribute(ATTR_USER_ID, userId);
            request.setAttribute(ATTR_ROLE, user.role());
            return true;
        } catch (BizException e) {
            throw e;
        } catch (Exception e) {
            throw new BizException(401, "登录凭证无效或已过期");
        }
    }
}
