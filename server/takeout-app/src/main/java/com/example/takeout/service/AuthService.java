package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import com.example.takeout.security.PasswordUtil;
import com.example.takeout.security.PaymentPasswordUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.Clock;
import java.time.format.DateTimeFormatter;

/**
 * 认证服务：注册、登录
 */
@Service
public class AuthService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final UserDao userDao;
    private final JwtUtil jwtUtil;
    private final SmsCodeVerifier smsCodeVerifier;
    private final Clock clock;
    private boolean demoRechargeEnabled;

    @Autowired
    public AuthService(UserDao userDao, JwtUtil jwtUtil, SmsCodeVerifier smsCodeVerifier,
                       @Value("${takeout.demo.recharge-enabled:false}") boolean demoRechargeEnabled) {
        this(userDao, jwtUtil, smsCodeVerifier, Clock.systemDefaultZone());
        this.demoRechargeEnabled = demoRechargeEnabled;
    }

    AuthService(UserDao userDao, JwtUtil jwtUtil, SmsCodeVerifier smsCodeVerifier, Clock clock) {
        this.userDao = userDao;
        this.jwtUtil = jwtUtil;
        this.smsCodeVerifier = smsCodeVerifier;
        this.clock = clock;
    }

    public AuthService(UserDao userDao, JwtUtil jwtUtil, SmsCodeVerifier smsCodeVerifier) {
        this(userDao, jwtUtil, smsCodeVerifier, Clock.systemDefaultZone());
    }

    /** Unit-test constructor; password reset remains closed unless a verifier is supplied. */
    public AuthService(UserDao userDao, JwtUtil jwtUtil) {
        this(userDao, jwtUtil, (phone, code) -> {
            throw new BizException("手机号或验证码不正确");
        });
    }

    /** Register only after consuming an email code bound to the proposed phone and mailbox. */
    @Transactional
    public User register(String username, String phone, String email, String code, String password, int role) {
        String normalizedEmail = registrationEmail(username, phone, email);
        if (password == null || password.length() < 6 || password.length() > 64) {
            throw new BizException("密码长度应为 6 至 64 位");
        }
        if (role != 0 && role != 1 && role != 3) {
            throw new BizException("角色不合法");
        }
        if (code == null || !code.matches("[0-9]{6}")) {
            throw new BizException("请输入 6 位邮箱验证码");
        }
        smsCodeVerifier.consume(registrationIdentity(phone, normalizedEmail), code);
        String now = LocalDateTime.now().format(FMT);
        return userDao.insert(username.trim(), phone, normalizedEmail, PasswordUtil.hash(password),
                role, role == 0 ? 20.0 : 0.0, now);
    }

    /** Check duplicates before requesting mail and again before account creation. */
    public String registrationEmail(String username, String phone, String email) {
        if (username == null || username.isBlank()) {
            throw new BizException("账号名不能为空");
        }
        if (username.trim().length() > 64) {
            throw new BizException("账号名最多 64 个字符");
        }
        if (phone == null || !phone.matches("1\\d{10}")) {
            throw new BizException("手机号格式不正确");
        }
        String normalizedEmail = requireEmail(email);
        if (userDao.existsByUsername(username.trim())) {
            throw new BizException("该账号已注册");
        }
        if (userDao.existsByPhone(phone)) {
            throw new BizException("该手机号已注册");
        }
        return normalizedEmail;
    }

    public String registrationIdentity(String phone, String email) {
        return "registration:" + phone + ":" + requireEmail(email);
    }

    /**
     * 登录：成功返回 (token, user)
     */
    public LoginResult login(String phone, String password) {
        return login(phone, password, null);
    }

    /** 按登录端校验账号角色，loginType 为空时兼容旧客户端。 */
    public LoginResult login(String phone, String password, String loginType) {
        User user = userDao.findByPhone(phone)
                .orElseThrow(() -> new BizException("账号或密码错误"));
        // status 已随 findByPhone 一并取回，无需再查一次库；禁用用户的存量 token 由 AuthInterceptor 统一失效
        if (user.status() != 1) {
            throw new BizException("账号已停用，请联系平台管理员");
        }
        if (!PasswordUtil.matches(password, user.password())) {
            throw new BizException("账号或密码错误");
        }
        if (loginType != null && !loginType.isBlank()) {
            int expectedRole = roleOf(loginType);
            if (user.role() != expectedRole) {
                throw new BizException(403, "登录端与账号角色不匹配，请切换正确的登录端");
            }
        }
        String token = jwtUtil.generateToken(user.id(), user.role(), user.passwordChangedAt());
        if (PasswordUtil.needsRehash(user.password())) {
            userDao.upgradePasswordHash(user.id(), user.password(), PasswordUtil.hash(password));
        }
        return new LoginResult(token, user.safe());
    }

    /**
     * 修改密码：校验原密码后写入新哈希，并记录改密时间。
     *
     * <p>改密时间会让**所有早于此刻签发的 token 立即失效**（含当前这一个），
     * 所以前端改密成功后必须回到登录页重新登录——这不是体验缺陷，是「改密即踢掉其他会话」的实现。</p>
     */
    @Transactional
    public void changePassword(long userId, String oldPassword, String newPassword) {
        User user = userDao.findByIdForUpdate(userId).orElseThrow(() -> new BizException("用户不存在"));
        if (oldPassword == null || !PasswordUtil.matches(oldPassword, user.password())) {
            throw new BizException("原密码不正确");
        }
        if (newPassword == null || newPassword.length() < 6) {
            throw new BizException("新密码长度至少 6 位");
        }
        if (PasswordUtil.matches(newPassword, user.password())) {
            throw new BizException("新密码不能与原密码相同");
        }
        userDao.updatePassword(userId, PasswordUtil.hash(newPassword),
                nextPasswordChangedAt(user.passwordChangedAt()));
    }

    /** 设置或重置独立支付密码；每次都用登录密码确认，绝不把登录密码当支付密码。 */
    @Transactional
    public void setPaymentPassword(long userId, String loginPassword, String paymentPassword) {
        User user = userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在"));
        if (loginPassword == null || !PasswordUtil.matches(loginPassword, user.password())) {
            throw new BizException("登录密码不正确");
        }
        if (paymentPassword == null || !paymentPassword.matches("[0-9]{6}")) {
            throw new BizException("支付密码必须为 6 位数字");
        }
        userDao.updatePaymentPassword(userId, PaymentPasswordUtil.hash(paymentPassword));
    }

    /** Codes are bound to immutable user ID, password purpose, and current contact details. */
    @Transactional
    public void resetPasswordByEmail(String phone, String email, String code, String newPassword) {
        if (newPassword == null || newPassword.length() < 6 || newPassword.length() > 64) {
            throw new BizException("新密码长度应为 6 至 64 位");
        }
        User user = recoveryUser(phone, email, true);
        smsCodeVerifier.consume(recoveryIdentity(user, "login"), code);
        userDao.updatePassword(user.id(), PasswordUtil.hash(newPassword),
                nextPasswordChangedAt(user.passwordChangedAt()));
    }

    @Transactional
    public void resetPaymentPasswordByEmail(String phone, String email, String code, String paymentPassword) {
        if (paymentPassword == null || !paymentPassword.matches("[0-9]{6}")) {
            throw new BizException("支付密码必须为 6 位数字");
        }
        User user = recoveryUser(phone, email, true);
        smsCodeVerifier.consume(recoveryIdentity(user, "payment"), code);
        userDao.updatePaymentPassword(user.id(), PaymentPasswordUtil.hash(paymentPassword));
    }

    public User recoveryUser(String phone, String email, boolean lock) {
        if (phone == null || !phone.matches("1\\d{10}")) {
            throw new BizException("手机号或邮箱不匹配");
        }
        String normalizedEmail = requireEmail(email);
        User user = (lock ? userDao.findByPhoneForUpdate(phone) : userDao.findByPhone(phone))
                .orElseThrow(() -> new BizException("手机号或邮箱不匹配"));
        if (user.status() != 1 || !phone.equals(user.phone())) {
            throw new BizException("手机号或邮箱不匹配");
        }
        if (!normalizedEmail.equals(normalizeEmail(user.email()))) {
            throw new BizException("邮箱错误，请输入该手机号绑定的邮箱");
        }
        return user;
    }

    public String recoveryIdentity(User user, String purpose) {
        if (!"login".equals(purpose) && !"payment".equals(purpose)) {
            throw new BizException("验证码用途不正确");
        }
        return "recovery:" + user.id() + ":" + purpose + ":" + user.phone() + ":" + normalizeEmail(user.email());
    }

    private int roleOf(String loginType) {
        return switch (loginType.trim().toUpperCase()) {
            case "USER", "CUSTOMER" -> 0;
            case "MERCHANT" -> 1;
            case "ADMIN" -> 2;
            case "RIDER" -> 3;
            default -> throw new BizException("登录端类型不合法，仅支持 USER、MERCHANT、ADMIN、RIDER");
        };
    }

    /**
     * 改密时间只有秒精度（历史表结构与 JWT 声明均如此），因此连续两次改密可能得到同一时间，
     * 让第一轮改密后签发的 token 逃过「早于改密时间」校验。保证新值严格晚于已记录值，
     * 同时兼容旧库中的空值或无法解析的历史内容。
     */
    private String nextPasswordChangedAt(String previous) {
        LocalDateTime now = LocalDateTime.now(clock).withNano(0);
        if (previous != null && !previous.isBlank()) {
            try {
                LocalDateTime previousTime = LocalDateTime.parse(previous, FMT);
                if (!now.isAfter(previousTime)) {
                    now = previousTime.plusSeconds(1);
                }
            } catch (java.time.format.DateTimeParseException ignored) {
                // 老库异常值按当前时间修复；后续 token 会使用规范格式。
            }
        }
        return now.format(FMT);
    }

    public User profile(long userId) {
        return userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在")).safe();
    }

    public User updateProfile(long userId, String username, String phone) {
        return updateProfileInternal(userId, username, phone, null, false);
    }

    public User updateProfile(long userId, String username, String phone, String email) {
        return updateProfileInternal(userId, username, phone, email, true);
    }

    private User updateProfileInternal(long userId, String username, String phone, String email,
                                       boolean updateEmail) {
        if (username == null || username.isBlank()) {
            throw new BizException("用户名不能为空");
        }
        if (phone == null || !phone.matches("1\\d{10}")) {
            throw new BizException("手机号格式不正确");
        }
        if (username.trim().length() > 64) {
            throw new BizException("账号最多 64 个字符");
        }
        if (userDao.existsByPhoneExceptUser(phone, userId)) {
            throw new BizException("该手机号已被其他账号使用");
        }
        if (userDao.existsByUsernameExceptUser(username.trim(), userId)) {
            throw new BizException("该账号已被其他用户使用");
        }
        if (!updateEmail) {
            userDao.updateProfile(userId, username.trim(), phone);
        } else {
            String normalizedEmail = requireEmail(email);
            userDao.updateProfile(userId, username.trim(), phone, normalizedEmail);
        }
        return profile(userId);
    }

    private String requireEmail(String value) {
        String normalized = normalizeEmail(value);
        if (normalized.isEmpty()) {
            throw new BizException("邮箱格式不正确");
        }
        return normalized;
    }

    private String normalizeEmail(String value) {
        if (value == null) return "";
        String normalized = value.trim().toLowerCase(java.util.Locale.ROOT);
        return normalized.length() <= 254 && normalized.matches(
                "^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$")
                ? normalized : "";
    }

    /** 测试充值：金额写入用户余额，返回数据库中的最新用户信息。 */
    @Transactional
    public User recharge(long userId, double amount) {
        if (!demoRechargeEnabled) {
            throw new BizException(403, "演示充值未开启");
        }
        if (!Double.isFinite(amount) || amount < 0.01 || amount > 10000) {
            throw new BizException("\u5145\u503c\u91d1\u989d\u9700\u5728 0.01 \u81f3 10000 \u5143\u4e4b\u95f4");
        }
        userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在"));
        userDao.addBalance(userId, round2(amount));
        return profile(userId);
    }

    private double round2(double value) {
        return Math.round(value * 100.0) / 100.0;
    }

    public record LoginResult(String token, User user) {
    }
}
