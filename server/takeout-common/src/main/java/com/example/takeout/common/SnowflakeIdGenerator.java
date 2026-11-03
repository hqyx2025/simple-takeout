package com.example.takeout.common;

import java.util.concurrent.locks.LockSupport;
import java.util.function.LongSupplier;

/**
 * 雪花（Snowflake）分布式 ID 生成器。
 *
 * <p><b>为什么需要它</b>：原订单号是「秒级时间戳 + 4 位随机数」。秒级粒度意味着
 * 同一秒内的并发下单只能靠 9000 个随机取值区分，订单量一大就是必然的 UNIQUE 冲突
 * （生日问题：同秒 1000 笔的碰撞概率超过 99%）。雪花把「毫秒 + 机器位 + 同毫秒序列号」
 * 组合起来，单机每毫秒可产出 4096 个不重复 ID，实例之间靠 workerId 区分。</p>
 *
 * <p><b>结构（64 位，正数用 63 位）</b>：
 * {@code 0 | 41 位毫秒时间戳(相对起始纪元) | 10 位 workerId | 12 位序列号}</p>
 *
 * <p>workerId 必须由部署配置分配，各进程独立且重启沿用；业务代码统一使用
 * {@link BusinessIdGenerator}，禁止自行创建同 workerId 的并行生成器。</p>
 */
public class SnowflakeIdGenerator {

    /** 起始纪元（2026-01-01T00:00:00Z），有效时间跨度为 2^41 毫秒。 */
    private static final long EPOCH = 1_767_225_600_000L;

    private static final int WORKER_BITS = 10;
    private static final int SEQUENCE_BITS = 12;

    private static final long MAX_WORKER_ID = (1L << WORKER_BITS) - 1;
    private static final long SEQUENCE_MASK = (1L << SEQUENCE_BITS) - 1;

    private static final int WORKER_SHIFT = SEQUENCE_BITS;
    private static final int TIMESTAMP_SHIFT = SEQUENCE_BITS + WORKER_BITS;

    /** 时钟回拨容忍上限（毫秒）：小幅回拨自旋等待，超过则抛错而不是产出可能重复的 ID。 */
    private static final long MAX_ROLLBACK_MS = 5L;

    private final long workerId;
    private final LongSupplier clock;

    private long lastTimestamp = -1L;
    private long sequence = 0L;

    public SnowflakeIdGenerator(long workerId) {
        this(workerId, System::currentTimeMillis);
    }

    /** 可注入时钟的构造器（测试时钟回拨用）。 */
    public SnowflakeIdGenerator(long workerId, LongSupplier clock) {
        if (!isValidWorkerId(workerId)) {
            throw new IllegalArgumentException("workerId 必须在 [0, " + MAX_WORKER_ID + "] 之间，实际=" + workerId);
        }
        if (clock == null) {
            throw new IllegalArgumentException("clock 不能为空");
        }
        this.workerId = workerId;
        this.clock = clock;
    }

    /** 生成下一个 ID。 */
    public synchronized long nextId() {
        long timestamp = clock.getAsLong();

        if (timestamp < lastTimestamp) {
            long rollback = lastTimestamp - timestamp;
            if (rollback > MAX_ROLLBACK_MS) {
                // 大幅回拨直接停止发号；唯一键重试无法修复系统时钟。
                throw new IllegalStateException("时钟回拨 " + rollback + "ms，拒绝生成 ID");
            }
            // 小幅回拨：自旋等到追回上一毫秒，避免重复
            timestamp = waitUntil(lastTimestamp);
        }

        long nextSequence = 0L;
        if (timestamp == lastTimestamp) {
            nextSequence = (sequence + 1) & SEQUENCE_MASK;
            if (nextSequence == 0) {
                // 同毫秒内序列号用尽（4096 个）：等到下一毫秒
                timestamp = waitUntil(lastTimestamp + 1);
            }
        }

        if (timestamp < EPOCH || timestamp - EPOCH >= (1L << 41)) {
            throw new IllegalStateException("当前时间超出雪花 ID 的有效纪元");
        }
        lastTimestamp = timestamp;
        sequence = nextSequence;
        return ((timestamp - EPOCH) << TIMESTAMP_SHIFT) | (workerId << WORKER_SHIFT) | sequence;
    }

    /** 生成字符串形式的 ID（直接用作订单号）。 */
    public String nextIdString() {
        return Long.toString(nextId());
    }

    /** 限时等待真实时钟恢复；不得伪造未来时间，否则重试或重启后可能重复发号。 */
    private long waitUntil(long targetTimestamp) {
        long deadline = System.nanoTime() + 10_000_000L;
        long timestamp = clock.getAsLong();
        while (timestamp < targetTimestamp) {
            if (System.nanoTime() >= deadline || Thread.currentThread().isInterrupted()) {
                throw new IllegalStateException("时钟未恢复，拒绝生成雪花 ID，请检查系统时间");
            }
            LockSupport.parkNanos(100_000L);
            timestamp = clock.getAsLong();
        }
        return timestamp;
    }

    public static boolean isValidWorkerId(long workerId) {
        return workerId >= 0 && workerId <= MAX_WORKER_ID;
    }

    public long workerId() {
        return workerId;
    }
}
