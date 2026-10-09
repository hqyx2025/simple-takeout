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

/**
 * 银行卡完整卡号的服务端加密。列表和日志永远只使用后四位；解密只在支付密码
 * 校验通过的揭示请求中发生。密钥从 JWT secret 派生，数据库不保存密钥。
 */
@Component
public final class BankCardCrypto {
    private static final String PREFIX = "v1:";
    private final SecretKeySpec key;
    private final SecureRandom random = new SecureRandom();

    public BankCardCrypto(@Value("${takeout.jwt.secret}") String secret) {
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException("银行卡加密需要服务端密钥");
        }
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                    ("takeout:bank-card:v1:" + secret).getBytes(StandardCharsets.UTF_8));
            key = new SecretKeySpec(digest, "AES");
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("银行卡加密不可用", e);
        }
    }

    public String encrypt(String cardNumber) {
        try {
            byte[] iv = new byte[12];
            random.nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(128, iv));
            byte[] ciphertext = cipher.doFinal(cardNumber.getBytes(StandardCharsets.UTF_8));
            return PREFIX + Base64.getEncoder().encodeToString(
                    ByteBuffer.allocate(iv.length + ciphertext.length).put(iv).put(ciphertext).array());
        } catch (GeneralSecurityException e) {
            throw new BizException(503, "银行卡信息保存失败，请稍后重试");
        }
    }

    public String decrypt(String value) {
        if (value == null || value.isBlank()) {
            throw new BizException(400, "该银行卡未录入完整卡号，请重新添加");
        }
        try {
            if (!value.startsWith(PREFIX)) {
                throw new IllegalArgumentException();
            }
            byte[] bytes = Base64.getDecoder().decode(value.substring(PREFIX.length()));
            if (bytes.length < 12 + 16 + 1) {
                throw new IllegalArgumentException();
            }
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key,
                    new GCMParameterSpec(128, Arrays.copyOf(bytes, 12)));
            return new String(cipher.doFinal(bytes, 12, bytes.length - 12), StandardCharsets.UTF_8);
        } catch (GeneralSecurityException | IllegalArgumentException e) {
            throw new BizException(503, "银行卡信息无法读取，请重新添加");
        }
    }
}
