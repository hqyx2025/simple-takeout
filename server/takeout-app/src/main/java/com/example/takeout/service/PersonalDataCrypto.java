package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.security.JwtUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.*;

/** Independent encryption and blind-index keys. No key material is stored with business data. */
@Component
public final class PersonalDataCrypto {
    private final Map<String, SecretKeySpec> keys = new LinkedHashMap<>();
    private final String currentId;
    private final SecretKeySpec indexKey;
    private final ObjectMapper json;
    private final SecureRandom random = new SecureRandom();

    public PersonalDataCrypto(@Value("${takeout.personal-data.encryption-secret}") String current,
            @Value("${takeout.personal-data.index-secret}") String index,
            @Value("${takeout.personal-data.previous-encryption-secrets:}") String previous,
            ObjectMapper json) {
        this.json = json;
        byte[] currentBytes = JwtUtil.decodeSecret(current);
        byte[] indexBytes = JwtUtil.decodeSecret(index);
        if (Arrays.equals(currentBytes, indexBytes)) throw new IllegalStateException("个人资料加密与检索必须使用独立密钥");
        try {
            currentId = add(currentBytes);
            if (!previous.isBlank()) for (String secret : previous.split(",", -1)) {
                byte[] old = JwtUtil.decodeSecret(secret.trim());
                if (Arrays.equals(old, indexBytes)) throw new IllegalStateException("旧加密密钥不能复用检索密钥");
                add(old);
            }
            indexKey = new SecretKeySpec(MessageDigest.getInstance("SHA-256").digest(indexBytes), "HmacSHA256");
        } catch (java.security.GeneralSecurityException failure) {
            throw new IllegalStateException("个人资料加密不可用", failure);
        }
    }

    private String add(byte[] secret) throws java.security.GeneralSecurityException {
        byte[] key = MessageDigest.getInstance("SHA-256").digest(secret);
        String id = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(key)).substring(0, 16);
        keys.put(id, new SecretKeySpec(key, "AES"));
        return id;
    }

    public String encrypt(String value, String purpose) {
        if (value == null) return null;
        try {
            byte[] iv = new byte[12]; random.nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, keys.get(currentId), new GCMParameterSpec(128, iv));
            cipher.updateAAD(purpose.getBytes(StandardCharsets.UTF_8));
            byte[] encrypted = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
            byte[] packed = java.nio.ByteBuffer.allocate(iv.length + encrypted.length).put(iv).put(encrypted).array();
            return "pd1:" + currentId + ":" + Base64.getEncoder().encodeToString(packed);
        } catch (java.security.GeneralSecurityException failure) { throw unavailable(); }
    }

    public String decrypt(String value, String purpose) {
        try {
            if (value == null || !value.startsWith("pd1:")) throw new IllegalArgumentException();
            String[] parts = value.split(":", 3);
            SecretKeySpec key = parts.length == 3 ? keys.get(parts[1]) : null;
            if (key == null) throw new IllegalArgumentException();
            byte[] bytes = Base64.getDecoder().decode(parts[2]);
            if (bytes.length < 28) throw new IllegalArgumentException();
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, Arrays.copyOf(bytes, 12)));
            cipher.updateAAD(purpose.getBytes(StandardCharsets.UTF_8));
            return new String(cipher.doFinal(bytes, 12, bytes.length - 12), StandardCharsets.UTF_8);
        } catch (java.security.GeneralSecurityException | IllegalArgumentException failure) { throw unavailable(); }
    }

    public String readLegacy(String value, String purpose) {
        if (value != null && value.matches("(?s)^pd[0-9]+:.*")) return decrypt(value, purpose);
        return value;
    }

    public boolean isCurrent(String value) { return value != null && value.startsWith("pd1:" + currentId + ":"); }

    public String hash(String purpose, String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256"); mac.init(indexKey);
            return Base64.getUrlEncoder().withoutPadding().encodeToString(mac.doFinal((purpose + "\0" + value).getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.GeneralSecurityException failure) { throw unavailable(); }
    }

    public String phoneToken(String phone) {
        if (phone == null) return null;
        if (phone.codePointCount(0, phone.length()) > 20) throw new BizException(400, "手机号超过长度限制");
        return "~" + hash("phone:exact", phone).substring(0, 19);
    }

    public String encryptJson(Object value, String purpose) {
        try { return encrypt(json.writeValueAsString(value), purpose); }
        catch (com.fasterxml.jackson.core.JsonProcessingException failure) { throw unavailable(); }
    }

    public <T> T decryptJson(String value, String purpose, Class<T> type) {
        try { return json.readValue(decrypt(value, purpose), type); }
        catch (com.fasterxml.jackson.core.JsonProcessingException failure) { throw unavailable(); }
    }

    private BizException unavailable() { return new BizException(503, "个人资料无法安全读取或保存，请联系管理员检查密钥"); }
}
