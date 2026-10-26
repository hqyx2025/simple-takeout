package com.example.takeout.config;

import com.example.takeout.security.JwtUtil;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** 在所有 profile 下阻止模板密钥及跨用途密钥复用。 */
@Component
public class SecuritySecretsGuard {
    public SecuritySecretsGuard(@Value("${takeout.jwt.secret}") String jwt,
                                @Value("${takeout.sms.hmac-secret}") String verification,
                                @Value("${takeout.assistant.encryption-secret}") String assistant,
                                @Value("${takeout.wallet.encryption-secret}") String wallet) {
        var keys = java.util.List.of(jwt, verification, assistant, wallet);
        keys.forEach(JwtUtil::decodeSecret);
        if (new java.util.HashSet<>(keys).size() != keys.size()) {
            throw new IllegalStateException("JWT、验证码、AI 和银行卡加密必须使用独立密钥");
        }
    }
}
