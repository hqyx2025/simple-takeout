package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.JwtUtil;
import com.example.takeout.security.PasswordUtil;
import org.springframework.stereotype.Service;

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
        User user = userDao.findByPhone(phone)
                .orElseThrow(() -> new BizException("账号或密码错误"));
        if (!PasswordUtil.matches(password, user.password())) {
            throw new BizException("账号或密码错误");
        }
        String token = jwtUtil.generateToken(user.id(), user.role());
        return new LoginResult(token, user.safe());
    }

    public User profile(long userId) {
        return userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在")).safe();
    }

    public record LoginResult(String token, User user) {
    }
}
