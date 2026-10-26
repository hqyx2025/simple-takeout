package com.example.takeout.controller;

import com.example.takeout.common.GlobalExceptionHandler;
import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.service.OrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class OrderPaymentControllerTest {

    private final OrderService orders = mock(OrderService.class);
    private final LoginRateLimiter limiter = mock(LoginRateLimiter.class);
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new OrderController(orders, limiter))
                .setControllerAdvice(new GlobalExceptionHandler()).build();
    }

    @Test
    void balancePasswordTravelsInBodyAndUsesAuthenticatedAccount() throws Exception {
        mvc.perform(post("/api/orders/13/pay").requestAttr("userId", 1L).param("channel", "BALANCE")
                        .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                        .content("{\"userId\":99,\"paymentPassword\":\"135790\"}"))
                .andExpect(status().isOk());
        verify(orders).payOrder(1L, 13L, "BALANCE", "QR", "135790");
        verify(limiter).recordAttempt("payment-password", "u1");
    }

    @Test
    void blockedPaymentAndQueryNeverReachOrderService() throws Exception {
        when(limiter.isBlocked("payment-password", "u1")).thenReturn(true);
        when(limiter.isBlocked("payment-query", "u1")).thenReturn(true);
        mvc.perform(post("/api/orders/13/pay").requestAttr("userId", 1L).param("channel", "BALANCE"))
                .andExpect(status().isTooManyRequests());
        mvc.perform(post("/api/orders/13/payment/query").requestAttr("userId", 1L))
                .andExpect(status().isTooManyRequests());
        verifyNoInteractions(orders);
    }

    @Test
    void missingChannelCannotTriggerImplicitBalancePayment() throws Exception {
        mvc.perform(post("/api/orders/13/pay").requestAttr("userId", 1L))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(orders);
    }

    @Test
    void explicitAlipayChannelReachesThePaymentService() throws Exception {
        mvc.perform(post("/api/orders/13/pay").requestAttr("userId", 1L).param("channel", "ALIPAY"))
                .andExpect(status().isOk());

        verify(orders).payOrder(1L, 13L, "ALIPAY", "QR");
    }

    @Test
    void appPaymentModeReachesThePaymentService() throws Exception {
        mvc.perform(post("/api/orders/13/pay").requestAttr("userId", 1L)
                        .param("channel", "ALIPAY").param("mode", "APP"))
                .andExpect(status().isOk());

        verify(orders).payOrder(1L, 13L, "ALIPAY", "APP");
    }

    @Test
    void activeQueryPassesTheAuthenticatedOwner() throws Exception {
        mvc.perform(post("/api/orders/13/payment/query").requestAttr("userId", 1L))
                .andExpect(status().isOk());

        verify(orders).refreshPaymentStatus(1L, 13L);
    }
}
