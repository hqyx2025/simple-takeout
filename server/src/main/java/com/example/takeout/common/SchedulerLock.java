package com.example.takeout.common;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.time.Duration;

/**
 * 定时任务单实例调度锁。
 *
 * <p><b>用途边界（很重要）</b>：这把锁只解决「同一轮扫描被多个实例重复执行」的<b>浪费</b>，
 * <b>不</b>用于防超卖、防重复扣款这类正确性问题。理由与
 * {@code md/Redis缓存与异步事件架构.md} §1 的既有论证一致：
 * 锁覆盖不到数据库写入，Redis 挂掉时反而更弱。真正的正确性由数据库条件更新保证
 * （{@code WHERE status = 0}、{@code WHERE escrow_status = 0}、Outbox 租约）。</p>
 *
 * <p><b>fail-open</b>：Redis 不可用或抛异常时<b>放行执行</b>。被保护的任务本身已是幂等/条件更新，
 * 多跑一次的代价远小于「因为一把锁让定时任务整体停摆」（超时订单不再自动取消）。
 * 这与 {@code LoginRateLimiter} 的降级口径完全一致。</p>
 *
 * <p><b>为什么不用 Redisson / 看门狗续租</b>：单轮任务耗时远小于锁 TTL，
 * 且任务重复执行的代价可忽略，续租机制带来的复杂度与故障面不划算。</p>
 */
@Component
public class SchedulerLock {

    private static final Logger log = LoggerFactory.getLogger(SchedulerLock.class);

    private static final String KEY_PREFIX = "takeout:job-lock:";

    private final ObjectProvider<StringRedisTemplate> redisProvider;

    @Value("${takeout.job.lock-enabled:true}")
    private boolean enabled = true;

    public SchedulerLock(ObjectProvider<StringRedisTemplate> redisProvider) {
        this.redisProvider = redisProvider;
    }

    /**
     * 尝试以单实例方式执行任务。
     *
     * @param jobName  任务名（锁键的一部分，不同任务必须用不同名字）
     * @param ttl      锁的存活时长；应略大于单轮任务耗时，避免死锁
     * @param action   任务动作；其抛出的异常会原样传播（调用方按既有约定记录，不中断调度）
     * @return true 表示本次确实执行了任务；false 表示锁被其他实例持有、已跳过
     */
    public boolean tryRun(String jobName, Duration ttl, Runnable action) {
        if (acquire(jobName, ttl)) {
            action.run();
            return true;
        }
        return false;
    }

    /**
     * 抢占锁。
     *
     * @return true 表示可以执行（抢到锁，或 Redis 不可用需 fail-open）
     */
    private boolean acquire(String jobName, Duration ttl) {
        if (!enabled) {
            return true;
        }
        StringRedisTemplate redis = redisProvider.getIfAvailable();
        if (redis == null) {
            // Redis 不可用：fail-open。任务自身幂等，多实例重复执行不会造成业务错误。
            return true;
        }
        try {
            String owner = InstanceId.current();
            Boolean acquired = redis.opsForValue().setIfAbsent(key(jobName), owner, ttl);
            return Boolean.TRUE.equals(acquired);
        } catch (Exception e) {
            // 加锁异常同样 fail-open，且不得向上抛：定时任务异常不能中断调度
            log.warn("[调度锁] 获取失败，本次放行执行 job={}", jobName, e);
            return true;
        }
    }

    private String key(String jobName) {
        return KEY_PREFIX + jobName;
    }
}