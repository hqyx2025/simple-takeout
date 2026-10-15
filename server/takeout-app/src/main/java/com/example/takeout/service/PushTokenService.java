package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.PushTokenDao;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;

@Service
public class PushTokenService {
    private final PushTokenDao dao;
    private final PushTokenCrypto crypto;

    public PushTokenService(PushTokenDao dao, PushTokenCrypto crypto) {
        this.dao = dao;
        this.crypto = crypto;
    }

    public void register(long userId, String token) {
        String valid = validate(token);
        dao.register(userId, hash(valid), crypto.encrypt(valid), System.currentTimeMillis());
    }

    public void unregister(long userId, String token) {
        if (valid(token)) dao.unregister(userId, hash(token));
    }

    public List<String> tokensForUser(long userId) {
        return dao.findEncryptedByUserId(userId).stream().map(crypto::decrypt).toList();
    }

    public String profileId(long userId) {
        return hash("takeout:push-profile:" + userId);
    }

    public static String validate(String token) {
        if (!valid(token)) {
            throw new BizException("推送设备注册信息无效");
        }
        return token;
    }

    private static boolean valid(String token) {
        return token != null && token.length() >= 32 && token.length() <= 4096
                && token.chars().noneMatch(Character::isISOControl);
    }

    private static String hash(String token) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is unavailable");
        }
    }
}
