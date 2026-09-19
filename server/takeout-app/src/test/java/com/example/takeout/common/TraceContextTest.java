package com.example.takeout.common;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 链路追踪标识测试。
 *
 * <p>钉住三件事：① 上游带了就沿用（多服务串成一条链）、没带才自己生成；
 * ② 非法/超长输入被归一化，不给日志注入与非法响应头留口子；
 * ③ MDC 必须能清理——Servlet 线程池复用线程，残留会让日志张冠李戴。</p>
 */
class TraceContextTest {

    @AfterEach
    void cleanUp() {
        TraceContext.clear();
    }

    @Test
    void reusesIncomingTraceIdSoServicesShareOneChain() {
        String incoming = "abc123def456";

        assertEquals(incoming, TraceContext.normalize(incoming),
                "上游已带 traceId 时必须沿用，否则跨服务串不成一条链");
    }

    @Test
    void returnsNullForMissingOrBlankIncoming() {
        assertNull(TraceContext.normalize(null), "没有上游值时应返回 null 让调用方自行生成");
        assertNull(TraceContext.normalize(""), "空串等同于没有");
        assertNull(TraceContext.normalize("   "), "纯空白等同于没有");
    }

    @Test
    void stripsUnsafeCharactersToPreventLogInjection() {
        // 换行会让一条日志被拆成多条，伪造出并不存在的日志行
        String injected = "abc\n2026-01-01 00:00:00 ERROR fake log line";

        String normalized = TraceContext.normalize(injected);

        assertTrue(normalized != null && !normalized.contains("\n"),
                "traceId 不得含换行，否则可伪造日志行：" + normalized);
        assertTrue(normalized != null && !normalized.contains(" "),
                "traceId 不得含空格：" + normalized);
    }

    @Test
    void truncatesOverlongIncomingValue() {
        String overlong = "a".repeat(500);

        String normalized = TraceContext.normalize(overlong);

        assertTrue(normalized != null && normalized.length() <= 64,
                "超长 traceId 必须截断，避免撑爆日志与响应头");
    }

    @Test
    void bindAndClearWorkOnMdc() {
        TraceContext.bind("trace-xyz");
        assertEquals("trace-xyz", TraceContext.current(), "绑定后必须能从 MDC 读回");
        assertEquals("trace-xyz", MDC.get(TraceContext.MDC_KEY), "MDC 键名必须与 logback pattern 一致");

        TraceContext.clear();
        assertEquals("", TraceContext.current(), "清理后不得残留（线程复用会串日志）");
        assertNull(MDC.get(TraceContext.MDC_KEY));
    }

    @Test
    void blankTraceIdIsNotBound() {
        TraceContext.bind(null);
        assertEquals("", TraceContext.current());

        TraceContext.bind("");
        assertEquals("", TraceContext.current(), "空值不应写入 MDC");
    }

    @Test
    void distinctThreadsDoNotShareTraceId() throws Exception {
        TraceContext.bind("main-thread-trace");

        String[] other = new String[1];
        Thread t = new Thread(() -> other[0] = TraceContext.current());
        t.start();
        t.join();

        assertEquals("", other[0], "MDC 是线程局部的，其他线程不得继承，否则并发日志会串");
        assertEquals("main-thread-trace", TraceContext.current(), "主线程的值不受影响");
        assertNotEquals("", TraceContext.current());
    }
}