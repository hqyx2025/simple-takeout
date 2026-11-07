package com.example.takeout.config;

import com.example.takeout.security.JwtUtil;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** 在所有 profile 下阻止模板密钥及跨用途密钥复用。 */
@Component
public class SecuritySecretsGuard {
    @org.springframework.beans.factory.annotation.Autowired
    public SecuritySecretsGuard(@Value("${takeout.jwt.secret}") String jwt,
                                @Value("${takeout.sms.hmac-secret}") String verification,
                                @Value("${takeout.assistant.encryption-secret}") String assistant,
                                @Value("${takeout.wallet.encryption-secret}") String wallet,
                                @Value("${takeout.personal-data.encryption-secret}") String personal,
                                @Value("${takeout.personal-data.index-secret}") String index) {
        requireDistinct(java.util.List.of(jwt, verification, assistant, wallet, personal, index));
    }

    public SecuritySecretsGuard(@Value("${takeout.jwt.secret}") String jwt,
                                @Value("${takeout.sms.hmac-secret}") String verification,
                                @Value("${takeout.assistant.encryption-secret}") String assistant,
                                @Value("${takeout.wallet.encryption-secret}") String wallet) {
        requireDistinct(java.util.List.of(jwt, verification, assistant, wallet));
    }

    private static void requireDistinct(java.util.List<String> keys) {
        var decoded = keys.stream().map(JwtUtil::decodeSecret).map(java.util.Base64.getEncoder()::encodeToString).toList();
        if (new java.util.HashSet<>(decoded).size() != keys.size()) {
            throw new IllegalStateException("JWT、验证码、AI、银行卡、个人资料加密和检索必须使用独立密钥");
        }
    }
}
