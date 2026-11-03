package com.example.takeout.common;

import org.springframework.stereotype.Component;

/**
 * 订单、支付和 ERP 单据共享一个进程级序列，业务编号通过接口始终作为字符串传递。
 * 每个发号进程必须分配独立的 0..1023 workerId，重启时沿用，禁止多个进程同时复用。
 * ponytail: 固定实例显式分配；动态扩容时替换为 Leaf 的协调分配，不能哈希或随机取号。
 */
@Component
public final class BusinessIdGenerator {
    /** Spring 启动时检查配置，避免直到用户下单才发现缺失。 */
    public BusinessIdGenerator() {
        generator();
    }

    private static final class Holder {
        private static final SnowflakeIdGenerator INSTANCE = new SnowflakeIdGenerator(configuredWorkerId(
                System.getProperty("takeout.snowflake.worker-id", System.getenv("TAKEOUT_SNOWFLAKE_WORKER_ID"))));
    }

    private static SnowflakeIdGenerator generator() {
        return Holder.INSTANCE;
    }

    static long configuredWorkerId(String value) {
        try {
            long workerId = Long.parseLong(value == null ? "" : value.trim());
            if (SnowflakeIdGenerator.isValidWorkerId(workerId)) return workerId;
        } catch (NumberFormatException ignored) {
            // 统一返回可操作的配置错误，不回退为随机或默认节点号。
        }
        throw new IllegalArgumentException("请为每个发号进程配置独立的 TAKEOUT_SNOWFLAKE_WORKER_ID (0..1023)，"
                + "或 -Dtakeout.snowflake.worker-id；重启沿用原值，禁止并发复用");
    }

    public static String nextId() {
        return generator().nextIdString();
    }

    public static long workerId() {
        return generator().workerId();
    }
}
