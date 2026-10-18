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
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;

@Service
public class SmsVerificationService implements SmsCodeVerifier {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final DefaultRedisScript<Long> CONSUME_SCRIPT = new DefaultRedisScript<>(
            "local value = redis.call('GET', KEYS[1]); "
                    + "if not value then return 0 end; "
                    + "if value == ARGV[1] then redis.call('DEL', KEYS[1]); redis.call('DEL', KEYS[2]); return 1 end; "
                    + "local tries = redis.call('INCR', KEYS[2]); "
                    + "if tries == 1 then redis.call('PEXPIRE', KEYS[2], redis.call('PTTL', KEYS[1])) end; "
                    + "if tries >= 5 then redis.call('DEL', KEYS[1]); redis.call('DEL', KEYS[2]) end; return 0",
            Long.class);

    private final StringRedisTemplate redis;
    private final SmsSender sender;
    private final byte[] hmacKey;
    private final Duration ttl;
    private final Duration cooldown;
    private final long dailyLimit;
    private final long hourlyLimit;

    public SmsVerificationService(StringRedisTemplate redis, SmsSender sender,
                                  @Value("${takeout.jwt.secret}") String signingSecret,
                                  @Value("${takeout.sms.code-ttl-seconds:900}") long ttlSeconds,
                                  @Value("${takeout.sms.cooldown-seconds:60}") long cooldownSeconds,
                                  @Value("${takeout.sms.daily-limit:5}") long dailyLimit,
                                  @Value("${takeout.sms.hourly-limit:100}") long hourlyLimit) {
        this(redis, sender, signingSecret, ttlSeconds, cooldownSeconds, dailyLimit, hourlyLimit, true);
    }

    /** Compatibility constructor used by unit tests and embedded callers. */
    public SmsVerificationService(StringRedisTemplate redis, SmsSender sender, String signingSecret,
                                  long ttlSeconds, long cooldownSeconds) {
        this(redis, sender, signingSecret, ttlSeconds, cooldownSeconds, 5, 100, false);
    }

    private SmsVerificationService(StringRedisTemplate redis, SmsSender sender, String signingSecret,
                                   long ttlSeconds, long cooldownSeconds, long dailyLimit,
                                   long hourlyLimit, boolean ignored) {
        if (signingSecret == null || signingSecret.length() < 32 || ttlSeconds < 60 || cooldownSeconds < 1) {
            throw new IllegalStateException("验证码配置无效");
        }
        this.redis = redis;
        this.sender = sender;
        this.hmacKey = signingSecret.getBytes(StandardCharsets.UTF_8);
        this.ttl = Duration.ofSeconds(ttlSeconds);
        this.cooldown = Duration.ofSeconds(cooldownSeconds);
        this.dailyLimit = dailyLimit;
        this.hourlyLimit = hourlyLimit;
    }

    public IssueResult issue(String identity) {
        return issue(identity, identity);
    }

    public IssueResult issue(String identity, String destination) {
        String identityHash = digest(identity);
        String codeKey = "takeout:verification:code:" + identityHash;
        String cooldownKey = "takeout:verification:cooldown:" + digest(destination);
        try {
            Boolean allowed = redis.opsForValue().setIfAbsent(cooldownKey, "1", cooldown);
            if (!Boolean.TRUE.equals(allowed)) {
                throw new BizException(429, "验证码请求过于频繁，请稍后再试");
            }
            if (!withinSendLimits(destination, cooldownKey)) {
                throw new BizException(429, "验证码请求过于频繁，请稍后再试");
            }
            String code = "%06d".formatted(RANDOM.nextInt(1_000_000));
            redis.opsForValue().set(codeKey, digest(identity + ":" + code), ttl);
            try {
                sender.sendVerificationCode(destination, code, identity);
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

    private boolean withinSendLimits(String destination, String cooldownKey) {
        try {
            String destinationHash = digest(destination);
            if (dailyLimit > 0) {
                String key = "takeout:verification:daily:" + destinationHash + ":" +
                        java.time.LocalDate.now(java.time.ZoneOffset.UTC);
                Long count = redis.opsForValue().increment(key);
                if (count != null) {
                    redis.expire(key, Duration.ofDays(1));
                    if (count > dailyLimit) {
                        redis.delete(cooldownKey);
                        return false;
                    }
                }
            }
            if (hourlyLimit > 0) {
                String key = "takeout:verification:hourly:" +
                        (Instant.now().getEpochSecond() / 3600);
                Long count = redis.opsForValue().increment(key);
                if (count != null) {
                    redis.expire(key, Duration.ofHours(1));
                    if (count > hourlyLimit) {
                        redis.delete(cooldownKey);
                        return false;
                    }
                }
            }
            return true;
        } catch (RuntimeException e) {
            // Redis failures are fail-closed for code storage, but do not turn a mock sender test into a false limit.
            throw e;
        }
    }

    @Override
    public void consume(String identity, String code) {
        if (!validIdentity(identity) || code == null || !code.matches("\\d{6}")) {
            throw invalidCode();
        }
        String identityHash = digest(identity);
        String codeKey = "takeout:verification:code:" + identityHash;
        String attemptsKey = "takeout:verification:attempts:" + identityHash;
        try {
            Long consumed = redis.execute(CONSUME_SCRIPT, List.of(codeKey, attemptsKey), digest(identity + ":" + code));
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
        return new BizException("验证码不正确或已过期，请重新获取");
    }

    private boolean validIdentity(String value) {
        return value != null && (value.matches("registration:1[0-9]{10}:[^\\s:]+@[^\\s:]+") || value.matches("recovery:[1-9][0-9]*:(login|payment):1[0-9]{10}:[^\\s:]+@[^\\s:]+") || value.matches("1\\d{10}") || value.matches(
                "1\\d{10}:[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+") || value.matches(
                "^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"));
    }

    public record IssueResult(String code, boolean mock) { }
}
