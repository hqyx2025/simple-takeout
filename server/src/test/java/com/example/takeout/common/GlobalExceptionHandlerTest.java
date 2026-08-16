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
}
