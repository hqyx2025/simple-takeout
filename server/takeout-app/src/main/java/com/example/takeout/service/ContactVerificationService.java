package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.PasswordUtil;
import com.example.takeout.service.thirdparty.HuaweiCloudSmsSender;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Proof is bound to account, destination, purpose, and the current credential version. */
@Service
public class ContactVerificationService {
    private final UserDao users;
    private final JdbcTemplate jdbc;
    private final SmsVerificationService codes;
    private final PersonalDataCrypto crypto;
    private final HuaweiCloudSmsSender phoneSender;

    public ContactVerificationService(UserDao users, JdbcTemplate jdbc, SmsVerificationService codes,
            PersonalDataCrypto crypto, Environment env, ObjectMapper json) {
        this.users = users; this.jdbc = jdbc; this.codes = codes; this.crypto = crypto;
        phoneSender = env.getProperty("takeout.contacts.phone-enabled", Boolean.class, false)
                ? new HuaweiCloudSmsSender(env.getProperty("takeout.sms.huawei.endpoint", ""),
                env.getProperty("takeout.sms.huawei.app-key", ""), env.getProperty("takeout.sms.huawei.app-secret", ""),
                env.getProperty("takeout.sms.huawei.sender", ""), env.getProperty("takeout.sms.huawei.signature", ""),
                env.getProperty("takeout.sms.huawei.template-id", ""), env.getProperty("takeout.sms.huawei.country-code", "86"), json)
                : null;
    }

    public record Status(boolean phoneVerified, boolean emailVerified, boolean phoneAvailable) { }
    public Status status(long userId) {
        User user = user(userId, false);
        return new Status(verified(user, "PHONE", user.phone()), verified(user, "EMAIL", user.email()), phoneSender != null);
    }

    public void send(long userId, String kind, String value, String password) {
        User user = user(userId, false); requirePassword(user, password);
        String destination = normalize(kind, value);
        if ("PHONE".equals(kind)) {
            if (phoneSender == null) throw new BizException(503, "手机号验证暂未开通，请保留当前手机号");
            codes.issue(identity(user, kind, destination), destination, phoneSender);
        } else codes.issue(identity(user, kind, destination), destination);
    }

    public void verify(User user, String kind, String value, String code) {
        codes.verify(identity(user, kind, normalize(kind, value)), code);
    }

    public void consume(User user, String kind, String value, String code) {
        String destination = normalize(kind, value);
        codes.consume(identity(user, kind, destination), code);
        markVerified(user.id(), kind, destination);
    }

    @Transactional
    public void verifyCurrent(long userId, String kind, String value, String password, String code) {
        User user = user(userId, true); requirePassword(user, password);
        String destination = normalize(kind, value);
        String current = "PHONE".equals(kind) ? user.phone() : user.email();
        if (!destination.equals(normalize(kind, current))) throw new BizException(409, "联系方式已变化，请刷新资料");
        consume(user, kind, destination, code);
    }

    public void markVerified(long userId, String kind, String value) {
        jdbc.update("INSERT INTO user_contact_verifications(user_id,kind,value_hash,verified_at) VALUES(?,?,?,NOW()) "
                + "ON DUPLICATE KEY UPDATE value_hash=VALUES(value_hash),verified_at=VALUES(verified_at)",
                userId, kind, crypto.hash("contact:" + kind, normalize(kind, value)));
    }

    private boolean verified(User user, String kind, String value) {
        if (value == null || value.isBlank()) return false;
        return Boolean.TRUE.equals(jdbc.queryForObject("SELECT EXISTS(SELECT 1 FROM user_contact_verifications "
                + "WHERE user_id=? AND kind=? AND value_hash=?)", Boolean.class,
                user.id(), kind, crypto.hash("contact:" + kind, normalize(kind, value))));
    }

    private String identity(User user, String kind, String value) {
        return "contact:" + user.id() + ":" + kind + ":" + crypto.hash("contact:" + kind, value) + ":" + value
                + ":" + crypto.hash("contact-version", user.passwordChangedAt() == null ? "" : user.passwordChangedAt());
    }
    private User user(long id, boolean lock) {
        User user = (lock ? users.findByIdForUpdate(id) : users.findById(id)).orElseThrow(() -> new BizException(401, "请重新登录"));
        if (user.status() != 1) throw new BizException(401, "账号已停用");
        return user;
    }
    private void requirePassword(User user, String password) {
        if (password == null || password.length() > 64 || !PasswordUtil.matches(password, user.password())) {
            throw new BizException(400, "当前密码不正确");
        }
    }
    public static String normalize(String kind, String value) {
        if ("PHONE".equals(kind)) { AuthService.requirePhone(value); return value; }
        if (!"EMAIL".equals(kind)) throw new BizException(400, "验证码用途不正确");
        String normalized = value == null ? "" : value.trim().toLowerCase(java.util.Locale.ROOT);
        if (normalized.length() > 254 || !normalized.matches("^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$")) {
            throw new BizException(400, "邮箱格式不正确");
        }
        return normalized;
    }
}
