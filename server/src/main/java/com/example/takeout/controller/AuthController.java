package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.model.User;
import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.security.TokenRevocationService;
import com.example.takeout.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 认证接口：注册 / 登录 / 登出 / 改密 / 个人信息
 *
 * <p>限流放在这一层：它需要来源 IP（HTTP 层信息），而 AuthService 只处理业务规则。
 * 登录对**失败**计数、成功即清零；注册对每次提交计数。</p>
 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService authService;
    private final LoginRateLimiter loginRateLimiter;
    private final TokenRevocationService tokenRevocationService;

    public AuthController(AuthService authService, LoginRateLimiter loginRateLimiter,
                          TokenRevocationService tokenRevocationService) {
        this.authService = authService;
        this.loginRateLimiter = loginRateLimiter;
        this.tokenRevocationService = tokenRevocationService;
    }

    @PostMapping("/register")
    public ApiResponse<User> register(@RequestBody RegisterRequest req, HttpServletRequest http) {
        String ip = LoginRateLimiter.clientIp(http);
        if (loginRateLimiter.isBlocked("register", ip)) {
            throw new BizException(429, "注册提交过于频繁，请稍后再试");
        }
        loginRateLimiter.recordAttempt("register", ip);
        return ApiResponse.ok(authService.register(req.username(), req.phone(), req.password(), req.role()).safe());
    }

    @PostMapping("/login")
    public ApiResponse<AuthService.LoginResult> login(@RequestBody LoginRequest req, HttpServletRequest http) {
        String ip = LoginRateLimiter.clientIp(http);
        if (loginRateLimiter.isBlocked("login", ip)) {
            throw new BizException(429, "登录尝试过于频繁，请稍后再试");
        }
        try {
            AuthService.LoginResult result = authService.login(req.phone(), req.password(), req.loginType());
            loginRateLimiter.reset("login", ip);
            return ApiResponse.ok(result);
        } catch (BizException e) {
            loginRateLimiter.recordAttempt("login", ip);
            throw e;
        }
    }

    /**
     * 登出：把当前 token 的 jti 记入黑名单，此后该 token 立即失效。
     * 前端即使请求失败也只清本地登录态（弱网下退出登录不能被网络拖住）。
     */
    @PostMapping("/logout")
    public ApiResponse<Void> logout(@RequestHeader(value = "Authorization", required = false) String authorization) {
        String token = authorization != null && authorization.startsWith("Bearer ")
                ? authorization.substring(7) : null;
        tokenRevocationService.revoke(token, "logout");
        return ApiResponse.ok();
    }

    /**
     * 修改密码：成功后当前 token 也会失效（改密时间早于新签发的 token），前端需回到登录页。
     */
    @PutMapping("/password")
    public ApiResponse<Void> changePassword(@RequestAttribute("userId") long userId,
                                            @RequestBody ChangePasswordRequest req) {
        authService.changePassword(userId, req.oldPassword(), req.newPassword());
        return ApiResponse.ok();
    }

    @GetMapping("/me")
    public ApiResponse<User> me(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(authService.profile(userId));
    }

    @PutMapping("/me")
    public ApiResponse<User> updateMe(@RequestAttribute("userId") long userId,
                                      @RequestBody ProfileUpdateRequest req) {
        return ApiResponse.ok(authService.updateProfile(userId, req.username(), req.phone()));
    }

    @PostMapping("/recharge")
    public ApiResponse<User> recharge(@RequestAttribute("userId") long userId,
                                      @RequestBody RechargeRequest req) {
        return ApiResponse.ok(authService.recharge(userId, req.amount()));
    }

    public record RegisterRequest(String username, String phone, String password, int role) {
    }

    public record LoginRequest(String phone, String password, String loginType) {
    }

    public record ProfileUpdateRequest(String username, String phone) {
    }

    public record RechargeRequest(double amount) {
    }

    public record ChangePasswordRequest(String oldPassword, String newPassword) {
    }
}