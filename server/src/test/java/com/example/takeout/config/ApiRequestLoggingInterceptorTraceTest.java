package com.example.takeout.config;

import com.example.takeout.common.TraceContext;
import com.example.takeout.security.AuthInterceptor;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 请求日志拦截器的 traceId 行为测试。
 *
 * <p>这层是 traceId 真正落地的地方：拦截器没写进 MDC，logback pattern 里的
 * {@code %X{traceId}} 就是空的，链路追踪等于没做。三个场景必须成立：
 * ① 上游带头则沿用；② 没带则生成并回写响应头；③ 请求结束清理 MDC（线程池复用不串日志）。</p>
 */
class ApiRequestLoggingInterceptorTraceTest {

    private final ApiRequestLoggingInterceptor interceptor = new ApiRequestLoggingInterceptor();

    @AfterEach
    void cleanUp() {
        TraceContext.clear();
    }

    @Test
    void reusesIncomingHeaderAndEchoesItBack() {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/orders");
        request.addHeader(TraceContext.HEADER, "upstream-trace-001");
        MockHttpServletResponse response = new MockHttpServletResponse();

        interceptor.preHandle(request, response, new Object());

        assertEquals("upstream-trace-001", TraceContext.current(), "必须沿用上游 traceId");
        assertEquals("upstream-trace-001", response.getHeader(TraceContext.HEADER),
                "必须把 traceId 回写响应头，前端报错才能带上它定位");

        interceptor.afterCompletion(request, response, new Object(), null);
        assertEquals("", TraceContext.current(), "请求结束必须清理 MDC");
        assertNull(MDC.get(TraceContext.MDC_KEY));
    }

    @Test
    void generatesTraceIdWhenUpstreamMissingIt() {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/orders");
        MockHttpServletResponse response = new MockHttpServletResponse();

        interceptor.preHandle(request, response, new Object());

        String generated = TraceContext.current();
        assertTrue(!generated.isBlank(), "上游没带时必须自己生成，不能留空");
        assertTrue(generated.matches("[A-Za-z0-9]+"), "生成的 traceId 应为安全字符：" + generated);
        assertEquals(generated, response.getHeader(TraceContext.HEADER), "生成的 traceId 同样要回写响应头");
    }

    @Test
    void clearsMdcEvenWhenHandlerThrows() {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/orders");
        MockHttpServletResponse response = new MockHttpServletResponse();
        interceptor.preHandle(request, response, new Object());

        // 处理链抛异常时也必须清理，否则异常请求的 traceId 会粘到后续请求日志上
        interceptor.afterCompletion(request, response, new Object(), new IllegalStateException("boom"));

        assertEquals("", TraceContext.current(), "异常路径同样必须清理 MDC");
    }

    @Test
    void doesNotLeakTraceIdBetweenSequentialRequests() {
        MockHttpServletRequest first = new MockHttpServletRequest("GET", "/api/stores");
        first.addHeader(TraceContext.HEADER, "trace-first");
        MockHttpServletResponse firstResp = new MockHttpServletResponse();
        interceptor.preHandle(first, firstResp, new Object());
        interceptor.afterCompletion(first, firstResp, new Object(), null);

        MockHttpServletRequest second = new MockHttpServletRequest("GET", "/api/goods");
        MockHttpServletResponse secondResp = new MockHttpServletResponse();
        interceptor.preHandle(second, secondResp, new Object());

        assertNotEquals("trace-first", TraceContext.current(),
                "第二个请求不得继承第一个请求的 traceId（线程复用场景）");
    }

    @Test
    void ignoresIllegalIncomingHeader() {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/stores");
        // 纯空白的头归一化后为空，应退化为自行生成而不是原样写入日志
        request.addHeader(TraceContext.HEADER, "   ");
        MockHttpServletResponse response = new MockHttpServletResponse();

        interceptor.preHandle(request, response, new Object());

        String traceId = TraceContext.current();
        assertTrue(!traceId.isBlank() && !traceId.equals("   "), "空白头必须退化为自己生成：" + traceId);
    }

    @Test
    void stripsControlCharactersFromIncomingHeader() {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/stores");
        // 带换行的头：换行会被剥掉，但残留的安全字符仍可沿用（不至于丢失上游链路）
        request.addHeader(TraceContext.HEADER, "upstream\ninjected");
        MockHttpServletResponse response = new MockHttpServletResponse();

        interceptor.preHandle(request, response, new Object());

        String traceId = TraceContext.current();
        assertTrue(!traceId.contains("\n") && !traceId.contains(" "),
                "控制字符必须被剥离，避免日志注入：" + traceId);
        assertEquals(traceId, response.getHeader(TraceContext.HEADER), "回写响应头的值必须与 MDC 一致");
    }

    @Test
    void recordsIdentityAttributesWithoutTouchingAuthInterceptor() {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/orders");
        request.setAttribute(AuthInterceptor.ATTR_USER_ID, 7L);
        MockHttpServletResponse response = new MockHttpServletResponse();

        interceptor.preHandle(request, response, new Object());
        interceptor.afterCompletion(request, response, new Object(), null);

        // 拦截器只读这些属性，不得修改（认证语义由 AuthInterceptor 独占）
        assertEquals(7L, request.getAttribute(AuthInterceptor.ATTR_USER_ID));
    }
}