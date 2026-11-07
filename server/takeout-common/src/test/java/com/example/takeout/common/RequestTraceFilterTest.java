package com.example.takeout.common;

import jakarta.servlet.ServletException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.junit.jupiter.api.Assertions.*;

class RequestTraceFilterTest {
    @AfterEach void clear() { TraceContext.clear(); }

    @Test void correlatesEvenRejectedRequestsAndRestoresTheCallingThread() throws Exception {
        TraceContext.bind("outer");
        var request = new MockHttpServletRequest("POST", "/api/orders");
        request.addHeader(TraceContext.HEADER, "request-123");
        var response = new MockHttpServletResponse();
        new RequestTraceFilter().doFilter(request, response, (req, res) -> {
            assertEquals("request-123", TraceContext.current());
            assertEquals("request-123", req.getAttribute(TraceContext.ATTR));
            ((jakarta.servlet.http.HttpServletResponse) res).setStatus(503);
        });
        assertEquals(503, response.getStatus());
        assertEquals("request-123", response.getHeader(TraceContext.HEADER));
        assertEquals("outer", TraceContext.current());
    }

    @Test void generatesSafeIdAndCleansMdcAfterAnException() {
        var response = new MockHttpServletResponse();
        assertThrows(ServletException.class, () -> new RequestTraceFilter().doFilter(
                new MockHttpServletRequest("GET", "/internal/events"), response,
                (req, res) -> { throw new ServletException("injected"); }));
        assertTrue(response.getHeader(TraceContext.HEADER).matches("[A-Za-z0-9]{32}"));
        assertEquals("", TraceContext.current());
    }
}
