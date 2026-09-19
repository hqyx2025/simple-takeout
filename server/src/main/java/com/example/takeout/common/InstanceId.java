package com.example.takeout.common;

import java.net.InetAddress;

/**
 * 当前进程的运行实例标识。
 *
 * <p>多实例部署下，某些标识必须「每实例不同」：</p>
 * <ul>
 *   <li>Redis Stream 的消费者名——所有实例都用同一个名字时，消费组会把它们当成
 *       <b>同一个消费者</b>，消息在实例间互相抢占，且无法各自消费。</li>
 *   <li>Outbox 行级认领的 owner——出问题时要知道「哪个实例搬走了这条事件」。</li>
 * </ul>
 *
 * <p>标识由「主机名 + 进程号 + 启动时刻碎片」拼成。它只用于区分与诊断，
 * <b>不承担唯一性前提</b>：即便两台机器碰撞也不影响正确性（消费组的 ACK 与
 * Outbox 的租约才是正确性来源）。</p>
 */
public final class InstanceId {

    /** 主机名保留长度：加上进程号等信息后必须仍能放进 VARCHAR(64) 的列宽。 */
    private static final int MAX_HOST_LENGTH = 32;

    private static final String ID = build();

    private InstanceId() {
    }

    /** 当前进程的实例标识，进程生命周期内恒定。 */
    public static String current() {
        return ID;
    }

    private static String build() {
        String host;
        try {
            host = InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            // 拿不到主机名不影响正确性，退化为通用前缀
            host = "host";
        }
        if (host == null || host.isBlank()) {
            host = "host";
        }
        // 列宽与消费者名的可读性：只保留安全字符
        host = host.replaceAll("[^A-Za-z0-9._-]", "_");
        if (host.length() > MAX_HOST_LENGTH) {
            host = host.substring(0, MAX_HOST_LENGTH);
        }
        long pid = ProcessHandle.current().pid();
        // 同一主机上 pid 不会并存；加启动时刻碎片让「重启后复用 pid」也能区分
        String suffix = Long.toHexString(System.nanoTime() & 0xffff);
        return host + "-" + pid + "-" + suffix;
    }
}