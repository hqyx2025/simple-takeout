package com.example.takeout.security;

import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Map;

/**
 * 登录 / 注册按来源 IP 限流（暴力破解防护）。
 *
 * <p>两个刻意的口径：</p>
 * <ul>
 *   <li><b>锁来源 IP，不锁账号</b>：按手机号锁定会让攻击者用别人的手机号试错，把受害者关在门外（DoS）。
 *       高频爆破被封的是发起方 IP，正常用户不会因他人尝试被牵连。</li>
 *   <li><b>计数存 Redis</b>：放进程内存会导致多实例各自计数（分散请求即可绕过）、重启即清零。
 *       Redis 不可用时一律放行——限流是加固手段，不能反过来变成登录不可用。</li>
 * </ul>
 */
@Component
public class LoginRateLimiter {

    private static final Logger log = LoggerFactory.getLogger(LoginRateLimiter.class);

    /** 限流动作：limit=窗口内允许次数，window=统计窗口（秒），block=超限封禁时长（秒）。 */
    private record Policy(int limit, int windowSeconds, int blockSeconds) {
    }

    private static final Policy DEFAULT_POLICY = new Policy(20, 60, 300);
    private static final Map<String, Policy> POLICIES = Map.of(
            "login", new Policy(10, 60, 600),
            "register", new Policy(5, 3600, 3600));

    private static final String KEY_PREFIX = "takeout:rl:";
    private static final String BLOCK_SUFFIX = ":blocked";

    private final ObjectProvider<StringRedisTemplate> redisProvider;

    @Value("${takeout.security.rate-limit.enabled:true}")
    private boolean enabled = true;

    public LoginRateLimiter(ObjectProvider<StringRedisTemplate> redisProvider) {
        this.redisProvider = redisProvider;
    }

    /** 该 IP 是否处于封禁中。Redis 异常时返回 false（放行）。 */
    public boolean isBlocked(String action, String ip) {
        StringRedisTemplate redis = redis();
        if (redis == null || ip == null || ip.isBlank()) {
            return false;
        }
        try {
            return Boolean.TRUE.equals(redis.hasKey(blockKey(action, ip)));
        } catch (Exception e) {
            log.warn("[登录限流] 查询封禁状态失败 action={}，本次放行", action, e);
            return false;
        }
    }

    /** 记一次失败/提交；窗口内累计到阈值即封禁该 IP。 */
    public void recordAttempt(String action, String ip) {
        StringRedisTemplate redis = redis();
        if (redis == null || ip == null || ip.isBlank()) {
            return;
        }
        Policy policy = POLICIES.getOrDefault(action, DEFAULT_POLICY);
        String counterKey = counterKey(action, ip);
        try {
            Long attempts = redis.opsForValue().increment(counterKey);
            if (attempts == null) {
                return;
            }
            if (attempts == 1L) {
                // 窗口从第一次尝试开始算：先设 TTL，后续自增不再重置窗口
                redis.expire(counterKey, Duration.ofSeconds(policy.windowSeconds()));
            }
            if (attempts >= policy.limit()) {
                redis.opsForValue().set(blockKey(action, ip), "1", Duration.ofSeconds(policy.blockSeconds()));
                redis.delete(counterKey);
                log.warn("[登录限流] IP 已被封禁 action={} ip={} 封禁秒数={}", action, ip, policy.blockSeconds());
            }
        } catch (Exception e) {
            log.warn("[登录限流] 记录尝试失败 action={}，本次放行", action, e);
        }
    }

    /** 登录成功：清掉该 IP 的失败计数与封禁标记。 */
    public void reset(String action, String ip) {
        StringRedisTemplate redis = redis();
        if (redis == null || ip == null || ip.isBlank()) {
            return;
        }
        try {
            redis.delete(counterKey(action, ip));
            redis.delete(blockKey(action, ip));
        } catch (Exception e) {
            log.warn("[登录限流] 重置计数失败 action={}", action, e);
        }
    }

    /**
     * 取真实来源 IP：反向代理/网关后 request.getRemoteAddr 拿到的是代理地址，
     * 会让所有请求共用一个计数而互相封禁，故优先取转发头。
     */
    public static String clientIp(HttpServletRequest request) {
        if (request == null) {
            return "";
        }
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        String realIp = request.getHeader("X-Real-IP");
        if (realIp != null && !realIp.isBlank()) {
            return realIp.trim();
        }
        String remote = request.getRemoteAddr();
        return remote == null ? "" : remote;
    }

    private StringRedisTemplate redis() {
        if (!enabled) {
            return null;
        }
        return redisProvider.getIfAvailable();
    }

    private String counterKey(String action, String ip) {
        return KEY_PREFIX + action + ":" + ip;
    }

    private String blockKey(String action, String ip) {
        return counterKey(action, ip) + BLOCK_SUFFIX;
    }
}