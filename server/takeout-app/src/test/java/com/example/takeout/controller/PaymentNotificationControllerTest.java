package com.example.takeout.controller;

import com.example.takeout.service.thirdparty.ExternalPaymentService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.Map;

import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class PaymentNotificationControllerTest {
    private final ExternalPaymentService payments = mock(ExternalPaymentService.class);
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new PaymentNotificationController(payments)).build();
    }

    @Test
    void alipayReturnsPlainSuccessOnlyAfterVerification() throws Exception {
        when(payments.acceptNotification(eq("ALIPAY"), eq(""), anyMap()))
                .thenReturn(ExternalPaymentService.NotificationResult.PAID);

        mvc.perform(post("/api/payment/alipay/notify")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED).param("sign", "signature"))
                .andExpect(status().isOk()).andExpect(content().string("success"));

        verify(payments).acceptNotification("ALIPAY", "", Map.of("sign", "signature"));
    }

    @Test
    void invalidAlipaySignatureNeverReceivesSuccessAcknowledgement() throws Exception {
        when(payments.acceptNotification(eq("ALIPAY"), eq(""), anyMap()))
                .thenThrow(new SecurityException("invalid signature"));

        mvc.perform(post("/api/payment/alipay/notify")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED).param("sign", "wrong"))
                .andExpect(status().isBadRequest()).andExpect(content().string("failure"));
    }

    @Test
    void wechatPassesTheOriginalBodyAndSignatureHeadersToVerifier() throws Exception {
        String raw = "{ \"resource\" : {\"ciphertext\":\"opaque\"} }";
        when(payments.acceptNotification(eq("WECHAT"), anyString(), anyMap()))
                .thenReturn(ExternalPaymentService.NotificationResult.PAID);

        mvc.perform(post("/api/payment/wechat/notify").contentType(MediaType.APPLICATION_JSON).content(raw)
                        .header("Wechatpay-Serial", "serial").header("Wechatpay-Nonce", "nonce")
                        .header("Wechatpay-Signature", "signature").header("Wechatpay-Timestamp", "timestamp"))
                .andExpect(status().isOk()).andExpect(content().json("{\"code\":\"SUCCESS\",\"message\":\"成功\"}"));

        verify(payments).acceptNotification("WECHAT", raw,
                Map.of("Wechatpay-Serial", "serial", "Wechatpay-Nonce", "nonce",
                        "Wechatpay-Signature", "signature", "Wechatpay-Timestamp", "timestamp"));
    }
}
