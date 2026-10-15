package com.example.takeout.config;

import com.example.takeout.common.TraceContext;
import com.example.takeout.dao.OperationAuditLogDao;
import com.example.takeout.security.AuthInterceptor;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.method.HandlerMethod;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ApiRequestLoggingInterceptorAuditTest {

    private final OperationAuditLogDao logs = mock(OperationAuditLogDao.class);
    private final ApiRequestLoggingInterceptor interceptor = new ApiRequestLoggingInterceptor(logs);

    @AfterEach
    void clearTrace() {
        TraceContext.clear();
    }

    @Test
    void recordsAdminMutationMetadataWithoutRequestBody() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("PUT", "/api/admin/users/17/status");
        request.setAttribute(AuthInterceptor.ATTR_USER_ID, 4L);
        request.setAttribute(AuthInterceptor.ATTR_ROLE, 2);
        request.addHeader(TraceContext.HEADER, "audit-trace-1");
        MockHttpServletResponse response = new MockHttpServletResponse();

        interceptor.preHandle(request, response, new Object());
        interceptor.afterCompletion(request, response, new HandlerMethod(this, "adminMutation"), null);

        verify(logs).insert(eq(4L), eq(2), eq(0L), eq(-1),
                eq("ApiRequestLoggingInterceptorAuditTest.adminMutation"), eq("PUT"),
                eq("/api/admin/users/17/status"), eq("SUCCESS"), eq(200), eq("audit-trace-1"), anyLong());
    }

    @Test
    void recordsOrderActionWithActorAndResultingStatus() throws Exception {
        when(logs.currentOrderStatus(12)).thenReturn(3);
        MockHttpServletRequest request = new MockHttpServletRequest("PUT", "/api/rider/orders/12/pickup");
        request.setAttribute(AuthInterceptor.ATTR_USER_ID, 8L);
        request.setAttribute(AuthInterceptor.ATTR_ROLE, 3);
        MockHttpServletResponse response = new MockHttpServletResponse();

        interceptor.preHandle(request, response, new Object());
        interceptor.afterCompletion(request, response, new HandlerMethod(this, "adminMutation"), null);

        verify(logs).insert(eq(8L), eq(3), eq(12L), eq(3),
                eq("ApiRequestLoggingInterceptorAuditTest.adminMutation"), eq("PUT"),
                eq("/api/rider/orders/12/pickup"), eq("SUCCESS"), eq(200), anyString(), anyLong());
    }

    @Test
    void doesNotRecordReadsOrNonAdminMutations() throws Exception {
        MockHttpServletRequest read = new MockHttpServletRequest("GET", "/api/admin/users");
        read.setAttribute(AuthInterceptor.ATTR_USER_ID, 4L);
        read.setAttribute(AuthInterceptor.ATTR_ROLE, 2);
        interceptor.preHandle(read, new MockHttpServletResponse(), new Object());
        interceptor.afterCompletion(read, new MockHttpServletResponse(), new Object(), null);

        MockHttpServletRequest nonAdmin = new MockHttpServletRequest("PUT", "/api/admin/users/17/status");
        nonAdmin.setAttribute(AuthInterceptor.ATTR_USER_ID, 7L);
        nonAdmin.setAttribute(AuthInterceptor.ATTR_ROLE, 1);
        interceptor.preHandle(nonAdmin, new MockHttpServletResponse(), new Object());
        interceptor.afterCompletion(nonAdmin, new MockHttpServletResponse(), new Object(), null);

        verify(logs, never()).insert(anyLong(), anyInt(), anyLong(), anyInt(), anyString(), anyString(),
                anyString(), anyString(), anyInt(), anyString(), anyLong());
    }

    public void adminMutation() {
    }
}
