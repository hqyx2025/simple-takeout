package com.example.takeout.security;

import jakarta.servlet.http.HttpServletRequest;
import com.example.takeout.common.BizException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.HashMap;

/** Redis 分布式限流；每次尝试同步保留有界本地窗口，用于 Redis 故障时继续保护。 */
@Component
public class LoginRateLimiter implements org.springframework.beans.factory.InitializingBean {

    private static final Logger log = LoggerFactory.getLogger(LoginRateLimiter.class);

    /** 限流动作：limit=窗口内允许次数，window=统计窗口（秒），block=超限封禁时长（秒）。 */
    private record Policy(int limit, int windowSeconds, int blockSeconds) {
    }

    private static final Policy DEFAULT_POLICY = new Policy(20, 60, 300);
    private static final Map<String, Policy> POLICIES = Map.ofEntries(
            Map.entry("register", new Policy(5, 3600, 3600)),
            // 验证码找回按来源 IP 限制，避免第三方邮件接口被刷。
            Map.entry("sms-code", new Policy(5, 60, 600)),
            Map.entry("email-code", new Policy(5, 60, 600)),
            Map.entry("captcha", new Policy(30, 60, 60)),
            Map.entry("email-code-phone", new Policy(5, 86400, 86400)),
            Map.entry("password-forgot", new Policy(5, 60, 600)),
            Map.entry("payment-password-forgot", new Policy(5, 60, 600)),
            // 验证前占用预算、成功清零，避免并发请求先验证后计数。
            Map.entry("bank-card-reveal", new Policy(5, 60, 600)),
            Map.entry("payment-password", new Policy(5, 60, 600)),
            Map.entry("payment-password-set", new Policy(5, 60, 600)),
            // 下单按账号（非 IP）限流：多店结算一次会连续提交 N 笔订单，故放宽到 10/min，
            Map.entry("order", new Policy(10, 60, 60)),
            Map.entry("browse", new Policy(120, 60, 60)),
            // 客户端每 3 秒自动查单，留出手动刷新余量。
            Map.entry("payment-query", new Policy(30, 60, 60)),
            Map.entry("refresh", new Policy(30, 60, 60)),
            Map.entry("logout", new Policy(30, 60, 60)),
            Map.entry("location", new Policy(30, 60, 60)),
            Map.entry("upload", new Policy(30, 3600, 3600)));

    private static final String KEY_PREFIX = "takeout:rl:";
    private static final String BLOCK_SUFFIX = ":blocked";
    private static final java.util.Set<String> LOGIN_ACTIONS = java.util.Set.of(
            "login", "login-total", "login-account-fail", "login-account-total");
    private static final long LOGIN_REDIS_SLOW_NANOS = java.util.concurrent.TimeUnit.MILLISECONDS.toNanos(250);
    private static final long LOGIN_REDIS_RETRY_NANOS = java.util.concurrent.TimeUnit.SECONDS.toNanos(5);
    private record RedisHealth(long retryAt, boolean probing) {}
    private final java.util.concurrent.atomic.AtomicReference<RedisHealth> loginRedisHealth =
            new java.util.concurrent.atomic.AtomicReference<>(new RedisHealth(0, false));
    private static final DefaultRedisScript<Long> RECORD = new DefaultRedisScript<>(
            "if redis.call('EXISTS', KEYS[2]) == 1 then return 0 end; "
            + "local n = redis.call('INCR', KEYS[1]); "
            + "if n == 1 then redis.call('EXPIRE', KEYS[1], ARGV[2]) end; "
            + "if n >= tonumber(ARGV[1]) then redis.call('SET', KEYS[2], '1', 'EX', ARGV[3]); "
            + "redis.call('DEL', KEYS[1]) end; return n", Long.class);

    private final ObjectProvider<StringRedisTemplate> redisProvider;
    private final Map<String, LocalWindow> local = new HashMap<>();
    private final Map<String, LocalWindow> overflow = new HashMap<>();
    private static final int MAX_LOCAL_KEYS = 10_000;
    private static final class LocalWindow {
        int attempts;
        long expiresAt;
        long blockedUntil;
    }

    @Value("${takeout.security.rate-limit.enabled:true}")
    private boolean enabled = true;

    @Value("${takeout.security.rate-limit.login-failure-limit:10}") private int loginFailureLimit = 10;
    @Value("${takeout.security.rate-limit.login-failure-window-seconds:60}") private int loginFailureWindow = 60;
    @Value("${takeout.security.rate-limit.login-failure-block-seconds:600}") private int loginFailureBlock = 600;
    @Value("${takeout.security.rate-limit.login-total-limit:60}") private int loginTotalLimit = 60;
    @Value("${takeout.security.rate-limit.login-total-window-seconds:60}") private int loginTotalWindow = 60;
    @Value("${takeout.security.rate-limit.login-total-block-seconds:60}") private int loginTotalBlock = 60;
    @Value("${takeout.security.rate-limit.login-account-limit:10}") private int loginAccountLimit = 10;
    @Value("${takeout.security.rate-limit.login-account-window-seconds:60}") private int loginAccountWindow = 60;
    @Value("${takeout.security.rate-limit.login-account-block-seconds:600}") private int loginAccountBlock = 600;
    @Value("${takeout.security.rate-limit.login-account-total-limit:30}") private int loginAccountTotalLimit = 30;
    @Value("${takeout.security.rate-limit.login-account-total-window-seconds:60}") private int loginAccountTotalWindow = 60;
    @Value("${takeout.security.rate-limit.login-account-total-block-seconds:60}") private int loginAccountTotalBlock = 60;

    public LoginRateLimiter(ObjectProvider<StringRedisTemplate> redisProvider) {
        this.redisProvider = redisProvider;
    }

    private Policy policyFor(String action) {
        return switch (action) {
            case "login" -> new Policy(loginFailureLimit, loginFailureWindow, loginFailureBlock);
            case "login-total" -> new Policy(loginTotalLimit, loginTotalWindow, loginTotalBlock);
            case "login-account-fail" -> new Policy(loginAccountLimit, loginAccountWindow, loginAccountBlock);
            case "login-account-total" -> new Policy(loginAccountTotalLimit, loginAccountTotalWindow, loginAccountTotalBlock);
            default -> POLICIES.getOrDefault(action, DEFAULT_POLICY);
        };
    }

    @Override public void afterPropertiesSet() {
        for (String action : java.util.List.of("login", "login-total", "login-account-fail", "login-account-total")) {
            Policy policy = policyFor(action);
            if (policy.limit() < 1 || policy.limit() > 10_000 || policy.windowSeconds() < 1
                    || policy.windowSeconds() > 86_400 || policy.blockSeconds() < 1 || policy.blockSeconds() > 86_400) {
                throw new IllegalStateException("登录限流配置超出允许范围: " + action);
            }
        }
    }

    /** Redis 与本地任一窗口封禁时拒绝。 */
    public boolean isBlocked(String action, String ip) {
        if (!enabled || ip == null || ip.isBlank()) return false;
        if (locallyBlocked(counterKey(action, ip)) || overflowBlocked(action, ip)) return true;
        StringRedisTemplate redis = redis();
        if (redis == null || ip == null || ip.isBlank()) {
            return false;
        }
        try {
            boolean blocked = Boolean.TRUE.equals(loginRedis(action, () -> redis.hasKey(blockKey(action, ip))));
            if (blocked) rememberRedisBlock(action, ip);
            return blocked;
        } catch (Exception e) {
            log.warn("[登录限流] Redis 查询失败，使用本地窗口 action={}", action);
            return false;
        }
    }

    /** 原子占用一次预算；即便并发请求均已通过预检，也不允许超额进入业务。 */
    public void recordAttempt(String action, String ip) {
        if (!enabled || ip == null || ip.isBlank()) return;
        int localResult = recordLocal(action, ip, false);
        if (localResult == 0) throw limited();
        StringRedisTemplate redis = redis();
        if (redis == null || ip == null || ip.isBlank()) {
            if (localResult == 2 && recordLocal(action, ip, true) == 0) throw limited();
            return;
        }
        Policy policy = policyFor(action);
        try {
            Long attempts = loginRedis(action, () -> redis.execute(RECORD, java.util.List.of(counterKey(action, ip), blockKey(action, ip)),
                    Integer.toString(policy.limit()), Integer.toString(policy.windowSeconds()), Integer.toString(policy.blockSeconds())));
            if (Long.valueOf(0).equals(attempts)) {
                rememberRedisBlock(action, ip);
                throw limited();
            }
            if (attempts == null && localResult == 2 && recordLocal(action, ip, true) == 0) throw limited();
        } catch (BizException e) {
            throw e;
        } catch (Exception e) {
            log.warn("[登录限流] Redis 记录失败，使用本地窗口 action={}", action);
            if (localResult == 2 && recordLocal(action, ip, true) == 0) throw limited();
        }
    }

    /** 仅供已验证的非登录操作清理专属预算；登录共享预算只能等待到期。 */
    public void reset(String action, String ip) {
        // 旧桶仅保留禁止清零的兼容保护，不再参与当前登录健康短路。
        if ("login-account".equals(action) || LOGIN_ACTIONS.contains(action)) return;
        synchronized (local) { local.remove(counterKey(action, ip)); }
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

    /** 仅使用容器按可信代理规则解析的地址；不自行信任请求头。 */
    public static String clientIp(HttpServletRequest request) {
        if (request == null) {
            return "";
        }
        String remote = request.getRemoteAddr();
        return remote == null ? "" : remote;
    }

    private boolean locallyBlocked(String key) {
        synchronized (local) {
            long now = System.currentTimeMillis();
            LocalWindow window = local.get(key);
            if (window != null && window.blockedUntil > now) return true;
            if (window != null && window.expiresAt <= now) local.remove(key);
            if (local.size() >= MAX_LOCAL_KEYS) {
                local.values().removeIf(w -> w.expiresAt <= now && w.blockedUntil <= now);
            }
            return false;
        }
    }

    /** 失败在验密后记录，预检也须读取满表降级桶，不能仅依赖 recordAttempt 的拒绝。 */
    private boolean overflowBlocked(String action, String identity) {
        synchronized (local) {
            String key = overflowKey(action, identity);
            LocalWindow window = overflow.get(key);
            if (window == null) return false;
            long now = System.currentTimeMillis();
            if (window.blockedUntil > now) return true;
            if (window.expiresAt <= now) overflow.remove(key);
            return false;
        }
    }

    /** 0=封禁，1=已占用，2=本地表满，由 Redis 决定；故障时转有界分动作桶。 */
    private int recordLocal(String action, String identity, boolean useOverflow) {
        synchronized (local) {
            long now = System.currentTimeMillis();
            if (local.size() >= MAX_LOCAL_KEYS) {
                local.values().removeIf(w -> w.expiresAt <= now && w.blockedUntil <= now);
            }
            // ponytail: 故障且表满时每动作 256 个共享桶，碰撞会更严格；恢复 Redis 后由分布式桶裁定。
            var windows = useOverflow ? overflow : local;
            String key = useOverflow ? overflowKey(action, identity) : counterKey(action, identity);
            if (!useOverflow && !local.containsKey(key) && local.size() >= MAX_LOCAL_KEYS) return 2;
            LocalWindow window = windows.computeIfAbsent(key, ignored -> new LocalWindow());
            if (window.blockedUntil > now) return 0;
            Policy policy = policyFor(action);
            if (window.expiresAt <= now) {
                window.attempts = 0;
                window.expiresAt = now + policy.windowSeconds() * 1000L;
            }
            if (++window.attempts >= policy.limit()) {
                window.blockedUntil = now + policy.blockSeconds() * 1000L;
                window.expiresAt = window.blockedUntil;
            }
            return 1;
        }
    }

    private BizException limited() { return new BizException(429, "操作过于频繁，请稍后再试"); }

    /** 没有远端剩余 TTL 时保守按完整政策时长保留已观察封禁，不能因短路下一次就放行。 */
    private void rememberRedisBlock(String action, String identity) {
        if (!LOGIN_ACTIONS.contains(action)) return;
        synchronized (local) {
            String key = counterKey(action, identity);
            boolean full = !local.containsKey(key) && local.size() >= MAX_LOCAL_KEYS;
            var windows = full ? overflow : local;
            if (full) key = overflowKey(action, identity);
            LocalWindow window = windows.computeIfAbsent(key, ignored -> new LocalWindow());
            long now = System.currentTimeMillis();
            if (window.blockedUntil <= now) {
                window.blockedUntil = now + policyFor(action).blockSeconds() * 1000L;
                window.expiresAt = window.blockedUntil;
            }
        }
    }

    /** 登录 Redis 慢调用/故障后退到已有本地窗口；冷却结束仅一个请求探测恢复。 */
    private <T> T loginRedis(String action, java.util.function.Supplier<T> operation) {
        if (!LOGIN_ACTIONS.contains(action)) return operation.get();
        RedisHealth ticket = loginRedisHealth.get();
        long start = System.nanoTime();
        if (ticket.retryAt() != 0) {
            if (ticket.probing() || start - ticket.retryAt() < 0) return null;
            RedisHealth probe = new RedisHealth(ticket.retryAt(), true);
            if (!loginRedisHealth.compareAndSet(ticket, probe)) return null;
            ticket = probe;
        }
        boolean completed = false;
        try {
            T result = operation.get();
            completed = true;
            // 已收到的封禁/拒绝结果仍交给调用方处理，不因慢调用丢弃。
            return result;
        } finally {
            long now = System.nanoTime();
            if (!completed || now - start >= LOGIN_REDIS_SLOW_NANOS) {
                if (loginRedisHealth.compareAndSet(ticket, new RedisHealth(now + LOGIN_REDIS_RETRY_NANOS, false))) {
                    log.warn("[登录限流] Redis 慢调用或故障，5 秒内使用本地窗口 action={}", action);
                }
            } else if (ticket.probing()) {
                // 使用状态对象身份作代次；旧的在途成功不能关闭后来打开的短路。
                loginRedisHealth.compareAndSet(ticket, new RedisHealth(0, false));
            }
        }
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

    private String overflowKey(String action, String identity) {
        return counterKey(action, Integer.toString(Math.floorMod(identity.hashCode(), 256)));
    }

    private String blockKey(String action, String ip) {
        return counterKey(action, ip) + BLOCK_SUFFIX;
    }
}
