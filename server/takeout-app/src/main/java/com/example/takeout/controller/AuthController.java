package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.model.User;
import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.security.TokenRevocationService;
import com.example.takeout.service.AuthService;
import com.example.takeout.service.RefreshTokenService;
import com.example.takeout.service.SmsVerificationService;
import com.example.takeout.service.PushTokenService;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
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
    private final RefreshTokenService refreshTokenService;
    private final SmsVerificationService smsVerificationService;
    private final PushTokenService pushTokenService;

    public AuthController(AuthService authService, LoginRateLimiter loginRateLimiter,
                          TokenRevocationService tokenRevocationService, RefreshTokenService refreshTokenService,
                          SmsVerificationService smsVerificationService, PushTokenService pushTokenService) {
        this.authService = authService;
        this.loginRateLimiter = loginRateLimiter;
        this.tokenRevocationService = tokenRevocationService;
        this.refreshTokenService = refreshTokenService;
        this.smsVerificationService = smsVerificationService;
        this.pushTokenService = pushTokenService;
    }

    @PostMapping("/register")
    public ApiResponse<User> register(@RequestBody RegisterRequest req, HttpServletRequest http) {
        String ip = LoginRateLimiter.clientIp(http);
        if (loginRateLimiter.isBlocked("register", ip)) {
            throw new BizException(429, "注册提交过于频繁，请稍后再试");
        }
        loginRateLimiter.recordAttempt("register", ip);
        return ApiResponse.ok(authService.register(req.username(), req.phone(), req.email(), req.code(), req.password(), req.role()).safe());
    }

    /** The server generates, stores, and sends the one-time email code. Only local mock mode returns it. */
    @PostMapping({"/email-code", "/sms-code"})
    public ApiResponse<EmailCodeResult> emailCode(@RequestBody EmailCodeRequest req, HttpServletRequest http) {
        String ip = LoginRateLimiter.clientIp(http);
        if (loginRateLimiter.isBlocked("email-code", ip)) {
            throw new BizException(429, "验证码请求过于频繁，请稍后再试");
        }
        loginRateLimiter.recordAttempt("email-code", ip);
        if (req == null) throw new BizException("请填写手机号和邮箱");
        SmsVerificationService.IssueResult result;
        if ("register".equals(req.purpose())) {
            String email = authService.registrationEmail(req.username(), req.phone(), req.email());
            result = smsVerificationService.issue(authService.registrationIdentity(req.phone(), email), email);
        } else {
            User user;
            try {
                user = authService.recoveryUser(req.phone(), req.email(), false);
            } catch (BizException e) {
                // Keep account existence and mailbox ownership indistinguishable on the public endpoint.
                throw new BizException(e.getCode() == 429 ? 429 : 400, "手机号或邮箱不匹配");
            }
            result = smsVerificationService.issue(authService.recoveryIdentity(user, req.purpose()), user.email());
        }
        return ApiResponse.ok(new EmailCodeResult(result.code(), result.mock()));
    }

    @PostMapping("/password/forgot")
    public ApiResponse<Void> forgotPassword(@RequestBody ForgotPasswordRequest req, HttpServletRequest http) {
        String ip = LoginRateLimiter.clientIp(http);
        if (loginRateLimiter.isBlocked("password-forgot", ip)) {
            throw new BizException(429, "找回密码请求过于频繁，请稍后再试");
        }
        loginRateLimiter.recordAttempt("password-forgot", ip);
        authService.resetPasswordByEmail(req.phone(), req.email(), req.code(), req.newPassword());
        return ApiResponse.ok();
    }

    @PostMapping("/payment-password/forgot")
    public ApiResponse<Void> forgotPaymentPassword(@RequestBody ForgotPaymentPasswordRequest req, HttpServletRequest http) {
        String ip = LoginRateLimiter.clientIp(http);
        if (loginRateLimiter.isBlocked("payment-password-forgot", ip)) {
            throw new BizException(429, "找回支付密码请求过于频繁，请稍后再试");
        }
        loginRateLimiter.recordAttempt("payment-password-forgot", ip);
        authService.resetPaymentPasswordByEmail(req.phone(), req.email(), req.code(), req.paymentPassword());
        return ApiResponse.ok();
    }

    @PostMapping("/login")
    public ApiResponse<AuthSessionResult> login(@RequestBody LoginRequest req, HttpServletRequest http) {
        String ip = LoginRateLimiter.clientIp(http);
        if (loginRateLimiter.isBlocked("login", ip)) {
            throw new BizException(429, "登录尝试过于频繁，请稍后再试");
        }
        try {
            AuthService.LoginResult result = authService.login(req.phone(), req.password(), req.loginType());
            loginRateLimiter.reset("login", ip);
            return ApiResponse.ok(new AuthSessionResult(result.token(), refreshTokenService.issue(result.user().id(), result.token()),
                    result.user()));
        } catch (BizException e) {
            loginRateLimiter.recordAttempt("login", ip);
            throw e;
        }
    }

    @PostMapping("/refresh")
    public ApiResponse<RefreshTokenService.RefreshResult> refresh(@RequestBody RefreshRequest req) {
        return ApiResponse.ok(refreshTokenService.refresh(req == null ? null : req.refreshToken()));
    }

    @PostMapping("/push-token")
    public ApiResponse<PushRegistrationResult> registerPushToken(@RequestAttribute("userId") long userId,
                                               @RequestBody PushTokenRequest req) {
        pushTokenService.register(userId, req == null ? null : req.token());
        return ApiResponse.ok(new PushRegistrationResult(pushTokenService.profileId(userId)));
    }

    /**
     * 登出：把当前 token 的 jti 记入黑名单，此后该 token 立即失效。
     * 前端即使请求失败也只清本地登录态（弱网下退出登录不能被网络拖住）。
     */
    @PostMapping("/logout")
    public ApiResponse<Void> logout(@RequestHeader(value = "Authorization", required = false) String authorization,
                                    @RequestBody(required = false) LogoutRequest req) {
        String token = authorization != null && authorization.startsWith("Bearer ")
                ? authorization.substring(7) : null;
        java.util.OptionalLong userId = tokenRevocationService.userIdIfValid(token);
        tokenRevocationService.revoke(token, "logout");
        refreshTokenService.revoke(req == null ? null : req.refreshToken());
        if (userId.isPresent() && req != null) pushTokenService.unregister(userId.getAsLong(), req.pushToken());
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

    /** 设置或重置独立支付密码；登录密码仅用于身份确认，不会作为支付密码保存。 */
    @PostMapping("/payment-password")
    public ApiResponse<Void> setPaymentPassword(@RequestAttribute("userId") long userId,
                                                @RequestBody PaymentPasswordRequest req,
                                                HttpServletRequest http) {
        String action = "payment-password";
        String identity = userId + ":" + LoginRateLimiter.clientIp(http);
        if (loginRateLimiter.isBlocked(action, identity)) {
            throw new BizException(429, "密码尝试过于频繁，请稍后再试");
        }
        try {
            authService.setPaymentPassword(userId, req.loginPassword(), req.paymentPassword());
            loginRateLimiter.reset(action, identity);
            return ApiResponse.ok();
        } catch (BizException e) {
            if ("登录密码不正确".equals(e.getMessage())) {
                loginRateLimiter.recordAttempt(action, identity);
            }
            throw e;
        }
    }

    @GetMapping("/me")
    public ApiResponse<User> me(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(authService.profile(userId));
    }

    @PutMapping("/me")
    public ApiResponse<User> updateMe(@RequestAttribute("userId") long userId,
                                      @RequestBody ProfileUpdateRequest req) {
        return ApiResponse.ok(authService.updateProfile(userId, req.username(), req.phone(), req.email(),
                req.currentPassword()));
    }

    @PostMapping("/recharge")
    public ApiResponse<User> recharge(@RequestAttribute("userId") long userId,
                                      @RequestBody RechargeRequest req) {
        return ApiResponse.ok(authService.recharge(userId, req.amount()));
    }

    public record RegisterRequest(String username, String phone, String email, String code, String password, int role) {
    }

    public record LoginRequest(String phone, String password, String loginType) {
    }

    public record AuthSessionResult(String token, String refreshToken, User user) {
    }

    public record RefreshRequest(String refreshToken) {
    }

    public record LogoutRequest(String refreshToken,
                                @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String pushToken) {
        @Override public String toString() { return "LogoutRequest[refreshToken=[redacted], pushToken=[redacted]]"; }
    }

    public record PushTokenRequest(@JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String token) {
        @Override public String toString() { return "PushTokenRequest[token=[redacted]]"; }
    }

    public record PushRegistrationResult(String profileId) { }

    public record ProfileUpdateRequest(String username, String phone, String email,
                                       @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String currentPassword) {
    }

    public record RechargeRequest(double amount) {
    }

    public record EmailCodeRequest(String phone, String email, String purpose, String username) {
    }

    public record EmailCodeResult(String code, boolean mock) {
    }

    public record ForgotPasswordRequest(String phone, String email, String code, String newPassword) { }

    public record ForgotPaymentPasswordRequest(String phone, String email, String code, String paymentPassword) { }

    public record ChangePasswordRequest(String oldPassword, String newPassword) {
    }

    public record PaymentPasswordRequest(@JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String loginPassword,
                                         @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String paymentPassword) {
        @Override public String toString() { return "PaymentPasswordRequest[passwords=[redacted]]"; }
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Void>> invalidBody() {
        // Jackson 解析错误可能包含输入的密码，不记录异常文本。
        return ResponseEntity.badRequest().body(ApiResponse.error(400, "请求参数格式不正确"));
    }
}
