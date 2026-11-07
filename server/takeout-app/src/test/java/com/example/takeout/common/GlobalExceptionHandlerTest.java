package com.example.takeout.common;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import static org.junit.jupiter.api.Assertions.assertEquals;

class GlobalExceptionHandlerTest {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    void businessUnauthorizedErrorUsesHttp401() {
        ResponseEntity<ApiResponse<Void>> response = handler.handleBiz(new BizException(401, "请重新登录"));

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertEquals(401, response.getBody().code());
        assertEquals("请重新登录", response.getBody().message());
    }

    @Test
    void internalErrorDoesNotExposeExceptionMessage() {
        ApiResponse<Void> response = handler.handleOther(new IllegalStateException("database password"));

        assertEquals(500, response.code());
        assertEquals("服务器内部错误，请稍后重试", response.message());
    }

    @Test
    void databaseLockConflictUses409WithoutExposingSql() {
        var response = handler.handleLockConflict(new org.springframework.dao.CannotAcquireLockException("sensitive SQL"));

        assertEquals(HttpStatus.CONFLICT, response.getStatusCode());
        assertEquals(409, response.getBody().code());
        assertEquals("订单操作冲突，请刷新状态后重试", response.getBody().message());
    }

    @Test void connectionAndTimeoutFailuresUse503ButConflictsAndSqlErrorsDoNotTripCircuit() {
        var request = new org.springframework.mock.web.MockHttpServletRequest();
        var response = handler.handleDatabase(new org.springframework.jdbc.CannotGetJdbcConnectionException("private password"), request);
        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, response.getStatusCode());
        assertEquals(Boolean.TRUE, request.getAttribute(DatabaseAvailability.FAILURE_ATTRIBUTE));
        assertEquals(false, response.getBody().message().contains("password"));
        org.junit.jupiter.api.Assertions.assertTrue(DatabaseAvailability.unavailable(new org.springframework.dao.QueryTimeoutException("slow")));
        org.junit.jupiter.api.Assertions.assertFalse(DatabaseAvailability.unavailable(new org.springframework.dao.CannotAcquireLockException("busy")));
        var sqlRequest = new org.springframework.mock.web.MockHttpServletRequest();
        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, handler.handleDatabase(new org.springframework.jdbc.BadSqlGrammarException(
                "task", "private SQL", new java.sql.SQLException("bad syntax", "42000")), sqlRequest).getStatusCode());
        org.junit.jupiter.api.Assertions.assertNull(sqlRequest.getAttribute(DatabaseAvailability.FAILURE_ATTRIBUTE));
        var commitRequest = new org.springframework.mock.web.MockHttpServletRequest();
        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, handler.handleDatabase(new org.springframework.transaction.TransactionSystemException(
                "commit result unknown", new java.sql.SQLTransientConnectionException("connection lost", "08007")), commitRequest).getStatusCode());
        assertEquals(Boolean.TRUE, commitRequest.getAttribute(DatabaseAvailability.FAILURE_ATTRIBUTE));
    }
}
