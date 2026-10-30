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
    void registrationFailureRetainsTheOriginalFifteenMinuteCodeForRetry() throws Exception {
        String secret = "registration-test-secret-at-least-thirty-two-characters";
        String email = UUID.randomUUID() + "@example.com";
        String phone = "13900139000";
        String identity = "registration:" + phone + ":" + email;
        var connection = new LettuceConnectionFactory("127.0.0.1", Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        connection.afterPropertiesSet();
        connection.start();
        var redis = new StringRedisTemplate(connection);
        var mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        String codeKey = "takeout:verification:code:" + HexFormat.of().formatHex(mac.doFinal(identity.getBytes(StandardCharsets.UTF_8)));
        String attemptsKey = codeKey.replace(":code:", ":attempts:");
        String cooldownKey = "takeout:verification:cooldown:" + HexFormat.of().formatHex(mac.doFinal(email.getBytes(StandardCharsets.UTF_8)));
        try {
            var sender = mock(SmsSender.class);
            when(sender.exposesCodeForDevelopment()).thenReturn(true);
            var codes = new SmsVerificationService(redis, sender, secret, 900, 60, 0, 0);
            String code = codes.issue(identity, email).code();
            long initialTtl = redis.getExpire(codeKey, java.util.concurrent.TimeUnit.MILLISECONDS);
            assertTrue(initialTtl > 890_000 && initialTtl <= 900_000, "Issued code must last fifteen minutes");
            var users = mock(com.example.takeout.dao.UserDao.class);
            var auth = new AuthService(users, mock(com.example.takeout.security.JwtUtil.class), codes);
            when(users.existsByUsername("taken")).thenReturn(true);
            BizException conflict = assertThrows(BizException.class,
                    () -> auth.register("taken", phone, email, code, "newpass123", 0));
            assertTrue(conflict.getMessage().contains("账号名"));
            assertTrue(redis.getExpire(codeKey, java.util.concurrent.TimeUnit.MILLISECONDS) > 0);
            assertTrue(redis.getExpire(codeKey, java.util.concurrent.TimeUnit.MILLISECONDS) <= initialTtl,
                    "Retry must retain the deadline rather than restart fifteen minutes");
            // Fast-forward the Redis deadline to the last fifteen seconds; the same code must still work.
            redis.expire(codeKey, Duration.ofSeconds(15));
            codes.verify(identity, code);
            when(users.insert(eq("available"), eq(phone), eq(email), anyString(), eq(0), eq(0.0), anyString()))
                    .thenReturn(new com.example.takeout.model.User(11, "available", "", phone, "hash", 0, 0, "now"));
            assertEquals(11, auth.register("available", phone, email, code, "newpass123", 0).id());
            assertFalse(redis.hasKey(codeKey));
            assertThrows(BizException.class, () -> codes.verify(identity, code));
            redis.delete(cooldownKey);
            String second = codes.issue(identity, email).code();
            String wrong = second.equals("000000") ? "000001" : "000000";
            for (int i = 0; i < 4; i++) assertThrows(BizException.class, () -> codes.verify(identity, wrong));
            codes.verify(identity, second); // Correct checks do not erase the bounded wrong-attempt counter.
            assertThrows(BizException.class, () -> codes.verify(identity, wrong));
            assertThrows(BizException.class, () -> codes.verify(identity, second));
            redis.delete(cooldownKey);
            String expired = codes.issue(identity, email).code();
            redis.expire(codeKey, Duration.ZERO);
            assertThrows(BizException.class, () -> codes.verify(identity, expired));
        } finally {
            redis.delete(List.of(codeKey, attemptsKey, cooldownKey));
            connection.destroy();
        }
    }

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
            String name = UUID.randomUUID().toString().replace("-", "");
            String mailbox = name + "@gmail.com";
            String alias = name.substring(0, 8) + "." + name.substring(8) + "+tag@googlemail.com";
            codes.issue("registration:13800138000:" + mailbox, mailbox);
            assertEquals(429, assertThrows(BizException.class,
                    () -> codes.issue("registration:13900139000:" + alias, alias)).getCode());
            verify(sender, never()).sendVerificationCode(eq(alias), anyString(), anyString());
        } finally {
            redis.delete(List.of(codeKey, attemptsKey, cooldownKey,
                    "takeout:verification:code:" + registrationHash, "takeout:verification:attempts:" + registrationHash));
            connection.destroy();
        }
    }
}
