package com.example.takeout.service;

import com.example.takeout.common.BizException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;

@Component
public final class PushTokenCrypto {
    private static final String PREFIX = "v1:";
    private final SecretKeySpec key;
    private final SecureRandom random = new SecureRandom();

    public PushTokenCrypto(@Value("${takeout.push.token-encryption-key:}") String secret) {
        if (secret == null || secret.isBlank()) {
            this.key = null;
            return;
        }
        if (secret.length() < 32) throw new IllegalStateException("Push token encryption key must be at least 32 characters");
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                    ("takeout:push-token:v1:" + secret).getBytes(StandardCharsets.UTF_8));
            key = new SecretKeySpec(digest, "AES");
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("Push token encryption is unavailable");
        }
    }

    public String encrypt(String token) {
        requireKey();
        try {
            byte[] iv = new byte[12];
            random.nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(128, iv));
            byte[] encrypted = cipher.doFinal(token.getBytes(StandardCharsets.UTF_8));
            return PREFIX + Base64.getEncoder().encodeToString(
                    ByteBuffer.allocate(iv.length + encrypted.length).put(iv).put(encrypted).array());
        } catch (GeneralSecurityException e) {
            throw new BizException(503, "推送设备注册失败，请稍后重试");
        }
    }

    public String decrypt(String value) {
        requireKey();
        try {
            if (value == null || !value.startsWith(PREFIX)) throw new IllegalArgumentException();
            byte[] bytes = Base64.getDecoder().decode(value.substring(PREFIX.length()));
            if (bytes.length < 29) throw new IllegalArgumentException();
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, Arrays.copyOf(bytes, 12)));
            return new String(cipher.doFinal(bytes, 12, bytes.length - 12), StandardCharsets.UTF_8);
        } catch (GeneralSecurityException | IllegalArgumentException e) {
            throw new BizException(503, "推送设备信息无法读取");
        }
    }

    public void requireKey() {
        if (key == null) throw new BizException(503, "推送尚未配置服务端加密密钥");
    }
}
