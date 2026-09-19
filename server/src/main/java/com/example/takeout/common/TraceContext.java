package com.example.takeout.common;

import org.slf4j.MDC;

/**
 * 链路追踪标识（traceId）。
 *
 * <p><b>为什么需要它</b>：拆成多服务后，一次用户请求会跨若干进程，
 * 靠「时间相近」把日志拼起来在并发下完全不可用。traceId 让每个进程都把同一个标识
 * 写进日志，排查时一次 grep 就能串起整条链路。</p>
 *
 * <p><b>取值的优先级</b>：上游已带 {@code X-Request-Id} 时<b>沿用</b>它——
 * 网关生成一次，下游各服务透传同一个值；没有才自己生成。这与「网关生成并透传」的
 * 目标架构一致，也让单体阶段与拆分后行为一致。</p>
 */
public final class TraceContext {

    /** 请求/响应头名称：既是入口读取来源，也是出口回写字段。 */
    public static final String HEADER = "X-Request-Id";

    /** MDC 键名；与 logback pattern 里的 {@code %X{traceId}} 对应。 */
    public static final String MDC_KEY = "traceId";

    /** 请求属性名：供拦截器在同一请求内取回。 */
    public static final String ATTR = TraceContext.class.getName() + ".traceId";

    /** 生成长度上限：防止上游塞入超长头导致日志与响应头异常。 */
    private static final int MAX_LENGTH = 64;

    private TraceContext() {
    }

    /**
     * 归一化上游传入的 traceId。
     *
     * @return 合法则返回原值（去除首尾空白并截断），非法/为空则返回 null 表示需自行生成
     */
    public static String normalize(String incoming) {
        if (incoming == null) {
            return null;
        }
        String value = incoming.trim();
        if (value.isEmpty()) {
            return null;
        }
        // 只保留安全字符：避免日志注入（换行）与响应头非法字符
        value = value.replaceAll("[^A-Za-z0-9._:-]", "");
        if (value.isEmpty()) {
            return null;
        }
        return value.length() > MAX_LENGTH ? value.substring(0, MAX_LENGTH) : value;
    }

    /** 绑定到当前线程 MDC；调用方必须在请求结束时 {@link #clear()}。 */
    public static void bind(String traceId) {
        if (traceId == null || traceId.isBlank()) {
            return;
        }
        MDC.put(MDC_KEY, traceId);
    }

    /** 取出当前线程 MDC 中的 traceId（无则返回空串）。 */
    public static String current() {
        String value = MDC.get(MDC_KEY);
        return value == null ? "" : value;
    }

    /** 清理当前线程 MDC。线程池复用线程，不清理会把上一个请求的 traceId 带到下一个。 */
    public static void clear() {
        MDC.remove(MDC_KEY);
    }
}