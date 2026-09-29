package com.example.takeout.common;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;

/**
 * 订单号生成器（雪花 ID + 唯一键冲突重试的唯一入口）。
 *
 * <p><b>为什么是进程级单例而不是注入的 Bean</b>：雪花的序列号语义是
 * 「每个进程每毫秒一个序列」，它必须在<b>整个进程内共享同一个实例</b>——
 * 若每个装配点各持一个生成器，两个实例会把各自的序列号从 0 开始，
 * 同毫秒内就会互相撞号。因此这里刻意用静态持有，而不是构造器注入。</p>
 *
 * <p>workerId 由 {@link InstanceId#current()} 派生
 * （主机名 + 进程号 + 启动碎片），无配置中心也能保证多实例不撞号。</p>
 */
public final class OrderIdGenerator {

    private static final SnowflakeIdGenerator GENERATOR =
            new SnowflakeIdGenerator(SnowflakeIdGenerator.workerIdFrom(InstanceId.current()));

    private OrderIdGenerator() {
    }

    private static final DateTimeFormatter ORDER_DATE = DateTimeFormatter.BASIC_ISO_DATE;

    /** 订单号：下单日期 yyyyMMdd + 7 位数字标识；数据库 UNIQUE 约束负责极端碰撞重试。 */
    public static String nextOrderNo() {
        long suffix = Math.floorMod(GENERATOR.nextId(), 10_000_000L);
        return LocalDate.now().format(ORDER_DATE) + String.format("%07d", suffix);
    }

    /** 当前实例派生的 workerId（诊断用：多实例排查撞号时对比该值）。 */
    public static long workerId() {
        return SnowflakeIdGenerator.workerIdFrom(InstanceId.current());
    }
}