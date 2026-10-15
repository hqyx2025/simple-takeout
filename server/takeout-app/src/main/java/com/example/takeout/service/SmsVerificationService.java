package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.service.thirdparty.SmsSender;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.time.Duration;
import java.util.HexFormat;
import java.util.List;

@Service
public class SmsVerificationService implements SmsCodeVerifier {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final DefaultRedisScript<Long> CONSUME_SCRIPT = new DefaultRedisScript<>(
            "local value = redis.call('GET', KEYS[1]); "
                    + "if value == ARGV[1] then redis.call('DEL', KEYS[1]); redis.call('DEL', KEYS[2]); return 1; "
                    + "end; return 0",
            Long.class);

    private final StringRedisTemplate redis;
    private final SmsSender sender;
    private final byte[] hmacKey;
    private final Duration ttl;
    private final Duration cooldown;

    public SmsVerificationService(StringRedisTemplate redis, SmsSender sender,
                                  @Value("${takeout.jwt.secret}") String signingSecret,
                                  @Value("${takeout.sms.code-ttl-seconds:300}") long ttlSeconds,
                                  @Value("${takeout.sms.cooldown-seconds:60}") long cooldownSeconds) {
        if (signingSecret == null || signingSecret.length() < 32 || ttlSeconds < 60 || cooldownSeconds < 1) {
            throw new IllegalStateException("短信验证码配置无效");
        }
        this.redis = redis;
        this.sender = sender;
        this.hmacKey = signingSecret.getBytes(StandardCharsets.UTF_8);
        this.ttl = Duration.ofSeconds(ttlSeconds);
        this.cooldown = Duration.ofSeconds(cooldownSeconds);
    }

    public IssueResult issue(String phone) {
        String phoneHash = digest(phone);
        String codeKey = "takeout:sms:code:" + phoneHash;
        String cooldownKey = "takeout:sms:cooldown:" + phoneHash;
        try {
            Boolean allowed = redis.opsForValue().setIfAbsent(cooldownKey, "1", cooldown);
            if (!Boolean.TRUE.equals(allowed)) {
                throw new BizException(429, "验证码请求过于频繁，请稍后再试");
            }
            String code = "%06d".formatted(RANDOM.nextInt(1_000_000));
            redis.opsForValue().set(codeKey, digest(phone + ":" + code), ttl);
            try {
                sender.sendSmsCode(phone, code);
            } catch (RuntimeException e) {
                redis.delete(List.of(codeKey, cooldownKey));
                throw new BizException(503, "验证码发送失败，请稍后重试");
            }
            return new IssueResult(sender.exposesCodeForDevelopment() ? code : "",
                    sender.exposesCodeForDevelopment());
        } catch (BizException e) {
            throw e;
        } catch (RuntimeException e) {
            throw new BizException(503, "验证码服务暂不可用，请稍后重试");
        }
    }

    @Override
    public void consume(String phone, String code) {
        if (phone == null || !phone.matches("1\\d{10}") || code == null || !code.matches("\\d{6}")) {
            throw invalidCode();
        }
        String phoneHash = digest(phone);
        String codeKey = "takeout:sms:code:" + phoneHash;
        String cooldownKey = "takeout:sms:cooldown:" + phoneHash;
        try {
            Long consumed = redis.execute(CONSUME_SCRIPT, List.of(codeKey, cooldownKey), digest(phone + ":" + code));
            if (!Long.valueOf(1L).equals(consumed)) {
                throw invalidCode();
            }
        } catch (BizException e) {
            throw e;
        } catch (RuntimeException e) {
            throw new BizException(503, "验证码服务暂不可用，请稍后重试");
        }
    }

    private String digest(String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(hmacKey, "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(value.getBytes(StandardCharsets.UTF_8)));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("验证码服务暂不可用");
        }
    }

    private BizException invalidCode() {
        return new BizException("手机号或验证码不正确");
    }

    public record IssueResult(String code, boolean mock) { }
}
