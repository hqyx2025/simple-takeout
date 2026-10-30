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
public class AuthService implements org.springframework.beans.factory.InitializingBean {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final UserDao userDao;
    private final JwtUtil jwtUtil;
    private final SmsCodeVerifier smsCodeVerifier;
    private final Clock clock;

    @Value("${takeout.security.rate-limit.login-verify-max-concurrent:2}")
    private int loginVerifyMaxConcurrent = 2;
    @Value("${takeout.security.rate-limit.login-verify-wait-millis:5000}")
    private int loginVerifyWaitMillis = 5000;
    private java.util.concurrent.Semaphore loginVerificationPermits = new java.util.concurrent.Semaphore(2, true);
    // 等待最多 32 个请求，延长等待时不能把所有 HTTP 工作线程留给登录队列。
    private java.util.concurrent.Semaphore loginAdmissionSlots = new java.util.concurrent.Semaphore(34);

    @Override public void afterPropertiesSet() {
        if (loginVerifyMaxConcurrent < 1 || loginVerifyMaxConcurrent > 16
                || loginVerifyWaitMillis < 0 || loginVerifyWaitMillis > 10000) {
            throw new IllegalStateException("登录验密并发必须为 1 至 16，等待必须为 0 至 10000 毫秒");
        }
        loginVerificationPermits = new java.util.concurrent.Semaphore(loginVerifyMaxConcurrent, true);
        loginAdmissionSlots = new java.util.concurrent.Semaphore(loginVerifyMaxConcurrent + 32);
    }

    @Autowired
    public AuthService(UserDao userDao, JwtUtil jwtUtil, SmsCodeVerifier smsCodeVerifier,
                       @Value("${takeout.demo.recharge-enabled:false}") boolean demoRechargeEnabled,
                       @Value("${takeout.demo.signup-balance:0}") double signupBalance) {
        this(userDao, jwtUtil, smsCodeVerifier, Clock.systemDefaultZone());
        if (demoRechargeEnabled || signupBalance != 0) {
            throw new IllegalStateException("演示充值与注册赠金已停用，请关闭相关配置");
        }
    }

    /** Compatibility constructor for tests and integrations using the previous configuration shape. */
    public AuthService(UserDao userDao, JwtUtil jwtUtil, SmsCodeVerifier smsCodeVerifier,
                       boolean demoRechargeEnabled) {
        this(userDao, jwtUtil, smsCodeVerifier, demoRechargeEnabled, 0);
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
        if (role != 0) {
            throw new BizException(403, "商户、骑手与管理员账号须由平台开通");
        }
        String normalizedEmail = registrationEmail(username, phone, email);
        requireNewPassword(password);
        if (code == null || !code.matches("[0-9]{6}")) {
            throw new BizException("请输入 6 位邮箱验证码");
        }
        String identity = registrationIdentity(phone, normalizedEmail);
        // Verify mailbox ownership before revealing conflicts; failed validation must retain the original TTL.
        smsCodeVerifier.verify(identity, code);
        requireRegistrationAvailable(username.trim(), phone);
        String now = LocalDateTime.now().format(FMT);
        try {
            User registered = userDao.insert(username.trim(), phone, normalizedEmail, PasswordUtil.hash(password),
                    0, 0.0, now);
            // Spend the code only after the write succeeds; expiry/replay rolls back this account transaction.
            smsCodeVerifier.consume(identity, code);
            return registered;
        } catch (org.springframework.dao.DuplicateKeyException e) {
            throw new BizException("账号名或手机号已被使用，请更换账号名或返回登录");
        }
    }

    private void requireRegistrationAvailable(String username, String phone) {
        if (userDao.existsByUsername(username)) throw new BizException("账号名已被使用，请更换账号名");
        if (userDao.existsByPhone(phone)) throw new BizException("手机号已注册，请返回登录或找回密码");
    }

    /** Validate mail-request inputs; reveal uniqueness conflicts only after mailbox ownership is verified. */
    public String registrationEmail(String username, String phone, String email) {
        if (username == null || username.isBlank()) {
            throw new BizException("账号名不能为空");
        }
        if (username.trim().length() > 64) {
            throw new BizException("账号名最多 64 个字符");
        }
        requirePhone(phone);
        String normalizedEmail = requireEmail(email);
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
        return login(phone, password, loginType, accountKey -> {});
    }

    /** 先取许可，再查一次账号；HTTP 层在回调中准入预算，之后才开始验密。 */
    public LoginResult login(String phone, String password, String loginType,
                             java.util.function.Consumer<String> admitAccount) {
        requirePhone(phone);
        if (password == null || password.length() > 64) throw new BizException("账号或密码错误");
        var permits = loginVerificationPermits;
        var slots = loginAdmissionSlots;
        if (!slots.tryAcquire()) {
            throw new BizException(503, "登录服务繁忙，请稍后重试");
        }
        try {
            try {
                if (!permits.tryAcquire(loginVerifyWaitMillis, java.util.concurrent.TimeUnit.MILLISECONDS)) {
                    throw new BizException(503, "登录服务繁忙，请稍后重试");
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new BizException(503, "登录服务繁忙，请稍后重试");
            }
            try {
                User user = userDao.findByPhone(phone).filter(found -> phone.equals(found.phone())).orElse(null);
                admitAccount.accept(user == null ? "unknown:" + phone : "u" + user.id());
                return authenticate(user, password, loginType);
            } finally {
                permits.release();
            }
        } finally {
            slots.release();
        }
    }

    private LoginResult authenticate(User user, String password, String loginType) {
        boolean matched = PasswordUtil.matchesForLogin(password, user == null ? null : user.password());
        // 账号存在性与停用状态均不在匿名登录失败文案中区分。
        if (user == null || user.status() != 1 || !matched) {
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

    @Transactional
    public LoginResult loginByEmailCode(String phone, String email, String code, String loginType,
                                       java.util.function.Consumer<String> admitAccount) {
        requirePhone(phone);
        User user = userDao.findByPhoneForUpdate(phone).filter(found -> phone.equals(found.phone())).orElse(null);
        admitAccount.accept(user == null ? "unknown:" + phone : "u" + user.id());
        String normalizedEmail = requireEmail(email);
        if (user == null || user.status() != 1 || !normalizedEmail.equals(normalizeEmail(user.email()))) {
            throw new BizException("手机号、邮箱或验证码不正确");
        }
        String identity = recoveryIdentity(user, "signin");
        smsCodeVerifier.verify(identity, code);
        if (loginType == null || loginType.isBlank() || user.role() != roleOf(loginType)) {
            throw new BizException(403, "登录端与账号角色不匹配，请切换正确的登录端");
        }
        String token = jwtUtil.generateToken(user.id(), user.role(), user.passwordChangedAt());
        smsCodeVerifier.consume(identity, code);
        return new LoginResult(token, user.safe());
    }

    /** 严格身份输入；不 trim、不移除隐形字符，避免与数据库等价比较产生不同口径。 */
    public static void requirePhone(String phone) {
        if (phone == null || !phone.matches("1[0-9]{10}")) throw new BizException("手机号格式不正确");
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
        requireNewPassword(newPassword);
        if (PasswordUtil.matches(newPassword, user.password())) {
            throw new BizException("新密码不能与原密码相同");
        }
        userDao.updatePassword(userId, PasswordUtil.hash(newPassword),
                nextPasswordChangedAt(user.passwordChangedAt()));
    }

    /** 设置或重置独立支付密码；每次都用登录密码确认，绝不把登录密码当支付密码。 */
    @Transactional
    public void setPaymentPassword(long userId, String loginPassword, String paymentPassword) {
        User user = userDao.findByIdForUpdate(userId).orElseThrow(() -> new BizException("用户不存在"));
        if (loginPassword == null || !PasswordUtil.matches(loginPassword, user.password())) {
            throw new BizException("登录密码不正确");
        }
        if (paymentPassword == null || !paymentPassword.matches("[0-9]{6}")) {
            throw new BizException("支付密码必须为 6 位数字");
        }
        userDao.updatePaymentPassword(userId, PaymentPasswordUtil.hash(paymentPassword));
        userDao.updatePassword(userId, user.password(), nextPasswordChangedAt(user.passwordChangedAt()));
    }

    /** Codes are bound to immutable user ID, password purpose, and current contact details. */
    @Transactional
    public void resetPasswordByEmail(String phone, String email, String code, String newPassword) {
        requireNewPassword(newPassword);
        User user = recoveryUser(phone, email, true);
        String identity = recoveryIdentity(user, "login");
        smsCodeVerifier.verify(identity, code);
        userDao.updatePassword(user.id(), PasswordUtil.hash(newPassword),
                nextPasswordChangedAt(user.passwordChangedAt()));
        smsCodeVerifier.consume(identity, code);
    }

    @Transactional
    public void resetPaymentPasswordByEmail(String phone, String email, String code, String paymentPassword) {
        if (paymentPassword == null || !paymentPassword.matches("[0-9]{6}")) {
            throw new BizException("支付密码必须为 6 位数字");
        }
        User user = recoveryUser(phone, email, true);
        String identity = recoveryIdentity(user, "payment");
        smsCodeVerifier.verify(identity, code);
        userDao.updatePaymentPassword(user.id(), PaymentPasswordUtil.hash(paymentPassword));
        userDao.updatePassword(user.id(), user.password(), nextPasswordChangedAt(user.passwordChangedAt()));
        smsCodeVerifier.consume(identity, code);
    }

    public User recoveryUser(String phone, String email, boolean lock) {
        if (phone == null || !phone.matches("1[0-9]{10}")) {
            throw new BizException("手机号或邮箱不匹配");
        }
        String normalizedEmail = requireEmail(email);
        User user = (lock ? userDao.findByPhoneForUpdate(phone) : userDao.findByPhone(phone))
                .orElseThrow(() -> new BizException("手机号或邮箱不匹配"));
        if (user.status() != 1 || !phone.equals(user.phone())) {
            throw new BizException("手机号或邮箱不匹配");
        }
        if (!normalizedEmail.equals(normalizeEmail(user.email()))) {
            throw new BizException("手机号或邮箱不匹配");
        }
        return user;
    }

    public String recoveryIdentity(User user, String purpose) {
        if (!"login".equals(purpose) && !"payment".equals(purpose) && !"signin".equals(purpose)) {
            throw new BizException("验证码用途不正确");
        }
        return "recovery:" + user.id() + ":" + purpose + ":" + user.phone() + ":" + normalizeEmail(user.email());
    }

    /** 新设口令采用显式字符集；已有密码的验证保持原样，查询仍使用绑定参数。 */
    static void requireNewPassword(String value) {
        if (value == null || value.length() < 6 || value.length() > 64) {
            throw new BizException("密码长度应为 6 至 64 位");
        }
        if (!value.matches("[A-Za-z0-9!@#$%^&*._+=?\\-]+")) {
            throw new BizException("密码仅支持数字、英文字母和 !@#$%^&*._+-=?，不含空格或其他字符");
        }
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

    @Transactional
    public User updateProfile(long userId, String username, String phone) {
        return updateProfileInternal(userId, username, phone, null, null, false);
    }

    @Transactional
    public User updateProfile(long userId, String username, String phone, String email) {
        return updateProfileInternal(userId, username, phone, email, null, true);
    }

    /** Update profile, requiring the current password when a recovery contact changes. */
    @Transactional
    public User updateProfile(long userId, String username, String phone, String email,
                              String currentPassword) {
        return updateProfileInternal(userId, username, phone, email, currentPassword, true);
    }

    private User updateProfileInternal(long userId, String username, String phone, String email,
                                       String currentPassword, boolean updateEmail) {
        if (username == null || username.isBlank()) {
            throw new BizException("用户名不能为空");
        }
        requirePhone(phone);
        if (username.trim().length() > 64) {
            throw new BizException("账号最多 64 个字符");
        }
        if (userDao.existsByPhoneExceptUser(phone, userId)) {
            throw new BizException("该手机号已被其他账号使用");
        }
        if (userDao.existsByUsernameExceptUser(username.trim(), userId)) {
            throw new BizException("该账号已被其他用户使用");
        }
        // 与改密、找回密码共用账号行锁，禁止资料更新回写并发改密前的旧哈希。
        User current = userDao.findByIdForUpdate(userId).orElseThrow(() -> new BizException("用户不存在"));
        String normalizedEmail = updateEmail ? requireEmail(email) : normalizeEmail(current.email());
        boolean contactChanged = !phone.equals(current.phone())
                || (updateEmail && !normalizedEmail.equals(normalizeEmail(current.email())));
        if (contactChanged && (currentPassword == null || !PasswordUtil.matches(currentPassword, current.password()))) {
            throw new BizException("修改手机号或邮箱需要验证当前密码");
        }
        if (!updateEmail) {
            userDao.updateProfile(userId, username.trim(), phone);
        } else {
            userDao.updateProfile(userId, username.trim(), phone, normalizedEmail);
        }
        if (contactChanged) {
            userDao.updatePassword(userId, current.password(), nextPasswordChangedAt(current.passwordChangedAt()));
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

    /** 保留旧客户端入口，任何配置和 profile 下均不得凭空增加可结算余额。 */
    public User recharge(long userId, double amount) {
        throw new BizException(403, "演示充值已停用");
    }

    public record LoginResult(String token, User user) {
    }
}
