package com.example.takeout.security;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/**
 * 密码哈希工具：SHA-256 + 固定盐（演示项目；生产可升级 BCrypt）
 */
public final class PasswordUtil {

    private static final String SALT = "simple-takeout-2026";

    private PasswordUtil() {
    }

    public static String hash(String rawPassword) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = digest.digest((SALT + rawPassword).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(bytes);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 不可用", e);
        }
    }

    public static boolean matches(String rawPassword, String hashed) {
        return hash(rawPassword).equals(hashed);
    }
}
