package com.example.takeout.security;

import com.example.takeout.common.BizException;
import com.example.takeout.common.DatabaseAvailability;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Semaphore;
import java.util.function.LongSupplier;
import java.time.Duration;

/** 认证查库之前保护两个竞争写入口。Redis 只负责削峰，最终业务结果仍由数据库事务决定。 */
@Component
@EnableConfigurationProperties(ClaimTrafficSettings.class)
public class ClaimTrafficGuard {
    public enum Action { COUPON, RIDER }
    private static final String PREFIX = "takeout:claim:{traffic}:";
    private static final DefaultRedisScript<Long> ADMIT = new DefaultRedisScript<>(
            "local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('PEXPIRE',KEYS[1],1000) end; " +
            "if n>tonumber(ARGV[1]) then return 1 end; " +
            "if ARGV[2]=='1' and not redis.call('SET',KEYS[2],ARGV[3],'NX','PX',ARGV[4]) then return 2 end; return 0", Long.class);
    private static final DefaultRedisScript<Long> RELEASE = new DefaultRedisScript<>(
            "if redis.call('GET',KEYS[1])==ARGV[1] then return redis.call('DEL',KEYS[1]) end; return 0", Long.class);

    private final ObjectProvider<StringRedisTemplate> redisProvider;
    private final JdbcTemplate jdbc;
    private final ClaimTrafficSettings settings;
    private final LongSupplier clock;
    private final Semaphore capacity;
    private final ConcurrentHashMap<String, String> orders = new ConcurrentHashMap<>();
    private final Window couponWindow = new Window();
    private final Window riderWindow = new Window();
    private final AvailabilityCircuit database;
    private final AvailabilityCircuit redisHealth;

    @Autowired
    public ClaimTrafficGuard(ObjectProvider<StringRedisTemplate> redisProvider, JdbcTemplate jdbc, ClaimTrafficSettings settings) {
        this(redisProvider, jdbc, settings, System::nanoTime);
    }

    ClaimTrafficGuard(ObjectProvider<StringRedisTemplate> redisProvider, JdbcTemplate jdbc,
                      ClaimTrafficSettings settings, LongSupplier clock) {
        this.redisProvider = redisProvider;
        this.jdbc = jdbc;
        this.settings = settings;
        this.clock = clock;
        capacity = new Semaphore(settings.maxConcurrentPerInstance());
        database = new AvailabilityCircuit("database", settings.databaseFailureThreshold(), settings.databaseCooldown(), clock);
        redisHealth = new AvailabilityCircuit("redis", 1, settings.redisCooldown(), clock);
    }

    /** 非阻塞准入；许可覆盖认证、业务事务提交以及请求结束，不在数据库连接池外另建等待队列。 */
    public Lease enter(Action action) {
        int limit = limit(action);
        if (!(action == Action.COUPON ? couponWindow : riderWindow).take(clock.getAsLong(), limit)) {
            throw new BizException(429, "请求较多，请稍后再试");
        }
        if (!capacity.tryAcquire()) throw new BizException(503, "当前请求较多，请稍后重试");
        AvailabilityCircuit.Ticket ticket = database.acquire();
        if (ticket == null) {
            capacity.release();
            throw unavailable();
        }
        return new Lease(action, ticket);
    }

    private int limit(Action action) { return action == Action.COUPON ? settings.couponPerSecond() : settings.riderPerSecond(); }
    private static BizException unavailable() { return new BizException(503, "服务暂时不可用，请稍后查询操作结果或重试"); }

    private static final class Window {
        private long startsAt;
        private int count;
        synchronized boolean take(long now, int limit) {
            if (count == 0 || now - startsAt >= Duration.ofSeconds(1).toNanos()) { startsAt = now; count = 0; }
            if (count >= limit) return false;
            count++;
            return true;
        }
    }

    public final class Lease implements AutoCloseable {
        private final Action action;
        private final AvailabilityCircuit.Ticket databaseTicket;
        private final String owner = UUID.randomUUID().toString();
        private String orderKey;
        private StringRedisTemplate leasedRedis;
        private boolean completed;
        private boolean closed;
        private boolean probed;

        private Lease(Action action, AvailabilityCircuit.Ticket ticket) { this.action = action; this.databaseTicket = ticket; }

        /** JWT 签名/角色预检后调用，仍在认证账号查库之前；同订单竞争跨实例合并。 */
        public void admit(String orderId) {
            if (orderId != null) {
                String key = PREFIX + "order:" + orderId;
                if (orders.putIfAbsent(key, owner) != null) throw new BizException(409, "该订单正在被处理，请稍后刷新");
                orderKey = key;
            }
            AvailabilityCircuit.Ticket redisTicket = redisHealth.acquire();
            StringRedisTemplate redis = redisTicket == null ? null : redisProvider.getIfAvailable();
            if (redis != null) {
                long start = clock.getAsLong();
                Long result = null;
                try {
                    result = redis.execute(ADMIT, orderKey == null ? List.of(PREFIX + "rate:" + action)
                                    : List.of(PREFIX + "rate:" + action, orderKey),
                            Integer.toString(limit(action)), orderKey == null ? "0" : "1", owner,
                            Long.toString(settings.orderLease().toMillis()));
                } catch (RuntimeException e) {
                    redisHealth.failure(redisTicket);
                    // 响应丢失时 SET NX 可能已经成功，保留 owner 供安全释放；业务仍由数据库兜底。
                    if (orderKey != null) leasedRedis = redis;
                }
                if (result != null) {
                    if (clock.getAsLong() - start >= Duration.ofMillis(250).toNanos()) redisHealth.failure(redisTicket);
                    else redisHealth.success(redisTicket);
                    if (result == 1) throw new BizException(429, "请求较多，请稍后再试");
                    if (result == 2) throw new BizException(409, "该订单正在被处理，请稍后刷新");
                    if (result != 0) throw new BizException(503, "服务暂时繁忙，请稍后重试");
                    if (orderKey != null) leasedRedis = redis;
                } else redisHealth.failure(redisTicket);
            } else if (redisTicket != null) redisHealth.abandon(redisTicket);

            // 熔断冷却后只允许一个真实数据库探测，未登录请求不能凭 401 响应关闭熔断。
            if (databaseTicket.probe()) {
                try {
                    jdbc.queryForObject("SELECT 1", Integer.class);
                    probed = true;
                } catch (RuntimeException e) {
                    if (DatabaseAvailability.unavailable(e)) { failed(); throw unavailable(); }
                    throw e;
                }
            }
        }

        public void succeeded(boolean authenticated) {
            if (!completed && (authenticated || probed)) { completed = true; database.success(databaseTicket); }
        }
        public void failed() {
            if (!completed) { completed = true; database.failure(databaseTicket); }
        }

        @Override public void close() {
            if (closed) return;
            closed = true;
            if (!completed) database.abandon(databaseTicket);
            try {
                if (leasedRedis != null) {
                    AvailabilityCircuit.Ticket redisTicket = redisHealth.acquire();
                    if (redisTicket != null) {
                        try {
                            leasedRedis.execute(RELEASE, List.of(orderKey), owner);
                            redisHealth.success(redisTicket);
                        } catch (RuntimeException e) { redisHealth.failure(redisTicket); }
                    }
                }
            } finally {
                if (orderKey != null) orders.remove(orderKey, owner);
                capacity.release();
            }
        }
    }
}
