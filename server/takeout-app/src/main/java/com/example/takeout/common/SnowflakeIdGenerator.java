package com.example.takeout.common;

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
 * <p><b>workerId 从哪来</b>：本项目不引入配置中心，因此 workerId 默认由实例标识
 * （主机名 + 进程号）派生——见 {@link #workerIdFrom(String)}。派生的信息位只有 1024 个取值，
 * 理论上不同实例可能撞号；撞号时的后果是「同一毫秒内两个实例各生成一批 ID 可能重复」，
 * 概率极低（10 位哈希碰撞 × 同毫秒并发），且 orders.order_no 的 UNIQUE 约束是最终兜底，
 * 因此这是刻意的简化：{@code ponytail: workerId 由实例标识哈希派生，上限 1024 个不同实例；
 * 超过该规模或要求零碰撞时改为配置中心/Redis INCR 分配 workerId。}</p>
 */
public class SnowflakeIdGenerator {

    /** 起始纪元（2026-01-01T00:00:00Z），缩短时间戳长度以延长可用年限。 */
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
                // 大幅回拨：宁可失败也不产出可能重复的 ID（调用方有唯一键+重试兜底）
                throw new IllegalStateException("时钟回拨 " + rollback + "ms，拒绝生成 ID");
            }
            // 小幅回拨：自旋等到追回上一毫秒，避免重复
            timestamp = waitUntil(lastTimestamp);
        }

        if (timestamp == lastTimestamp) {
            sequence = (sequence + 1) & SEQUENCE_MASK;
            if (sequence == 0) {
                // 同毫秒内序列号用尽（4096 个）：等到下一毫秒
                timestamp = waitUntil(lastTimestamp + 1);
            }
        } else {
            sequence = 0L;
        }

        lastTimestamp = timestamp;
        return ((timestamp - EPOCH) << TIMESTAMP_SHIFT) | (workerId << WORKER_SHIFT) | sequence;
    }

    /** 生成字符串形式的 ID（直接用作订单号）。 */
    public String nextIdString() {
        return Long.toString(nextId());
    }

    /**
     * 等到真实时钟追回到目标毫秒。
     *
     * <p>{@code clock} 是测试可注入的，因此这里用「反复询问时钟」而非 {@code Thread.sleep} 实现，
     * 保证注入固定时钟时不会真的睡死（测试里的固定时钟由序列号自增保证不重复）。</p>
     */
    private long waitUntil(long targetTimestamp) {
        long timestamp = clock.getAsLong();
        int spins = 0;
        while (timestamp < targetTimestamp) {
            if (++spins > 10_000) {
                // 时钟停摆或大幅回拨：停止自旋，交给调用方按 UNIQUE 冲突重试
                return targetTimestamp;
            }
            Thread.onSpinWait();
            timestamp = clock.getAsLong();
        }
        return timestamp;
    }

    public static boolean isValidWorkerId(long workerId) {
        return workerId >= 0 && workerId <= MAX_WORKER_ID;
    }

    /**
     * 从实例标识派生 workerId。
     *
     * <p>同一实例标识必须恒定（否则重启后 ID 可能撞上旧值），因此用确定性哈希而非随机数。
     * 空值/非法输入也要返回合法 workerId，保证服务永远能启动。</p>
     */
    public static long workerIdFrom(String instanceId) {
        if (instanceId == null || instanceId.isBlank()) {
            return 0L;
        }
        long hash = 1125899906842597L; // 大素数种子
        for (int i = 0; i < instanceId.length(); i++) {
            hash = 31 * hash + instanceId.charAt(i);
        }
        return Math.floorMod(hash, MAX_WORKER_ID + 1);
    }
}