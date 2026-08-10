package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.model.User;
import com.example.takeout.service.AuthService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 认证接口：注册 / 登录 / 个人信息
 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/register")
    public ApiResponse<User> register(@RequestBody RegisterRequest req) {
        return ApiResponse.ok(authService.register(req.username(), req.phone(), req.password(), req.role()));
    }

    @PostMapping("/login")
    public ApiResponse<AuthService.LoginResult> login(@RequestBody LoginRequest req) {
        return ApiResponse.ok(authService.login(req.phone(), req.password()));
    }

    @GetMapping("/me")
    public ApiResponse<User> me(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(authService.profile(userId));
    }

    public record RegisterRequest(String username, String phone, String password, int role) {
    }

    public record LoginRequest(String phone, String password) {
    }
}
