package com.example.takeout.controller;

import com.example.takeout.common.GlobalExceptionHandler;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.service.OrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class OrderRefundControllerTest {
    private final OrderService orders = mock(OrderService.class);
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new OrderController(orders, mock(LoginRateLimiter.class)))
                .setControllerAdvice(new GlobalExceptionHandler()).build();
    }

    @Test
    void customerHistoryUsesAuthenticatedOwnerAndDoesNotExposeRequestKey() throws Exception {
        when(orders.refundHistory(2, 7)).thenReturn(List.of(new RefundRecord(9, 7, 2, 4,
                "QUALITY_ISSUE", "汤洒了", 13, "REJECTED", "2026-10-26 10:00:00", "", "请补充说明")));
        mvc.perform(get("/api/orders/7/refunds").requestAttr("userId", 2L).requestAttr("role", 0))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].id").value(9))
                .andExpect(jsonPath("$.data[0].requestKey").doesNotExist())
                .andExpect(jsonPath("$.data[0].request_key").doesNotExist());
        verify(orders).refundHistory(2, 7);
    }

    @Test
    void merchantRiderAndAdminCannotReadOrApplyThroughCustomerRefundEndpoints() throws Exception {
        for (int role : new int[]{1, 2, 3}) {
            mvc.perform(get("/api/orders/7/refunds").requestAttr("userId", 2L).requestAttr("role", role))
                    .andExpect(status().isForbidden());
            mvc.perform(post("/api/orders/7/refund").requestAttr("userId", 2L).requestAttr("role", role))
                    .andExpect(status().isForbidden());
        }
        verifyNoInteractions(orders);
    }

    @Test
    void refundSubmissionPassesOptionalKeyAndIgnoresForgedOwner() throws Exception {
        mvc.perform(post("/api/orders/7/refund").requestAttr("userId", 2L).requestAttr("role", 0)
                        .contentType("application/json")
                        .content("{\"userId\":99,\"reasonType\":\"OTHER\",\"reason\":\"餐损\",\"idempotencyKey\":\"refund-7\"}"))
                .andExpect(status().isOk());
        verify(orders).applyRefund(2, 7, "OTHER", "餐损", "refund-7");
    }
}
