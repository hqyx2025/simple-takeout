package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.service.thirdparty.SmsSender;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;

import java.time.Duration;
import java.util.List;
import java.util.UUID;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_TEST_REDIS_PORT", matches = "\\d+")
class RecoveryCodeRedisTest {
    @Test
    void realRedisRejectsCrossAccountPurposeReplayAndFiveWrongAttempts() throws Exception {
        String secret = "recovery-test-secret-at-least-thirty-two-characters";
        String email = UUID.randomUUID() + "@example.com";
        String identity = "recovery:991:login:13800138000:" + email;
        String otherAccount = identity.replace(":991:", ":992:");
        String otherPurpose = identity.replace(":login:", ":payment:");
        LettuceConnectionFactory connection = new LettuceConnectionFactory("127.0.0.1", Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        connection.afterPropertiesSet();
        connection.start();
        StringRedisTemplate redis = new StringRedisTemplate(connection);
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        String hash = HexFormat.of().formatHex(mac.doFinal(identity.getBytes(StandardCharsets.UTF_8)));
        String cooldownHash = HexFormat.of().formatHex(mac.doFinal(email.getBytes(StandardCharsets.UTF_8)));
        String codeKey = "takeout:verification:code:" + hash;
        String attemptsKey = "takeout:verification:attempts:" + hash;
        String cooldownKey = "takeout:verification:cooldown:" + cooldownHash;
        String registration = "registration:13800138000:" + email;
        String registrationHash = HexFormat.of().formatHex(mac.doFinal(registration.getBytes(StandardCharsets.UTF_8)));
        try {
            SmsSender sender = mock(SmsSender.class);
            when(sender.exposesCodeForDevelopment()).thenReturn(true);
            SmsVerificationService codes = new SmsVerificationService(redis, sender, secret, 300, 60);
            String code = codes.issue(identity, email).code();
            verify(sender).sendVerificationCode(eq(email), eq(code), eq(identity));
            assertThrows(BizException.class, () -> codes.consume(otherAccount, code));
            assertThrows(BizException.class, () -> codes.consume(otherPurpose, code));
            codes.consume(identity, code);
            assertThrows(BizException.class, () -> codes.consume(identity, code));
            assertThrows(BizException.class, () -> codes.issue(otherAccount, email));
            redis.delete(cooldownKey);
            String second = codes.issue(identity, email).code();
            String wrong = second.equals("000000") ? "000001" : "000000";
            for (int attempt = 0; attempt < 5; attempt++) {
                assertThrows(BizException.class, () -> codes.consume(identity, wrong));
            }
            assertThrows(BizException.class, () -> codes.consume(identity, second));
            redis.delete(cooldownKey);
            String expired = codes.issue(identity, email).code();
            redis.expire(codeKey, Duration.ZERO);
            assertThrows(BizException.class, () -> codes.consume(identity, expired));
            redis.delete(cooldownKey);
            String signupCode = codes.issue(registration, email).code();
            assertThrows(BizException.class, () -> codes.consume(identity, signupCode));
            assertThrows(BizException.class, () -> codes.consume(registration.replace("13800138000", "13900139000"), signupCode));
            codes.consume(registration, signupCode);
            assertThrows(BizException.class, () -> codes.consume(registration, signupCode));
        } finally {
            redis.delete(List.of(codeKey, attemptsKey, cooldownKey,
                    "takeout:verification:code:" + registrationHash, "takeout:verification:attempts:" + registrationHash));
            connection.destroy();
        }
    }
}
