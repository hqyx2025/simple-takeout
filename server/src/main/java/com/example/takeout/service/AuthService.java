package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import com.example.takeout.security.PasswordUtil;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * 认证服务：注册、登录
 */
@Service
public class AuthService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final UserDao userDao;
    private final JwtUtil jwtUtil;

    public AuthService(UserDao userDao, JwtUtil jwtUtil) {
        this.userDao = userDao;
        this.jwtUtil = jwtUtil;
    }

    /**
     * 注册（role：0=用户 1=商户）
     */
    public User register(String username, String phone, String password, int role) {
        if (username == null || username.isBlank()) {
            throw new BizException("用户名不能为空");
        }
        if (phone == null || !phone.matches("1\\d{10}")) {
            throw new BizException("手机号格式不正确");
        }
        if (password == null || password.length() < 6) {
            throw new BizException("密码长度至少 6 位");
        }
        if (role != 0 && role != 1) {
            throw new BizException("角色不合法");
        }
        if (userDao.existsByPhone(phone)) {
            throw new BizException("该手机号已注册");
        }
        double balance = role == 0 ? 20.0 : 0.0;
        String now = LocalDateTime.now().format(FMT);
        return userDao.insert(username, phone, PasswordUtil.hash(password), role, balance, now);
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
        if (userDao.isDisabled(user.id())) {
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
        String token = jwtUtil.generateToken(user.id(), user.role());
        return new LoginResult(token, user.safe());
    }

    private int roleOf(String loginType) {
        return switch (loginType.trim().toUpperCase()) {
            case "USER", "CUSTOMER" -> 0;
            case "MERCHANT" -> 1;
            case "ADMIN" -> 2;
            default -> throw new BizException("登录端类型不合法，仅支持 USER、MERCHANT、ADMIN");
        };
    }

    public User profile(long userId) {
        return userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在")).safe();
    }

    public User updateProfile(long userId, String username, String phone) {
        if (username == null || username.isBlank()) {
            throw new BizException("用户名不能为空");
        }
        if (phone == null || !phone.matches("1\\d{10}")) {
            throw new BizException("手机号格式不正确");
        }
        if (userDao.existsByPhoneExceptUser(phone, userId)) {
            throw new BizException("该手机号已被其他账号使用");
        }
        userDao.updateProfile(userId, username.trim(), phone);
        return profile(userId);
    }

    /** 测试充值：金额写入用户余额，返回数据库中的最新用户信息。 */
    @Transactional
    public User recharge(long userId, double amount) {
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
