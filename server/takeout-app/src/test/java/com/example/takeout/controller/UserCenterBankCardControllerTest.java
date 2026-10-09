package com.example.takeout.controller;

import com.example.takeout.model.BankCard;
import com.example.takeout.service.UserCenterService;
import com.example.takeout.common.BizException;
import com.example.takeout.security.LoginRateLimiter;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class UserCenterBankCardControllerTest {
    private final UserCenterService service = mock(UserCenterService.class);

    @Test
    void addUsesAuthenticatedAccountAndReturnsExistingMaskedContract() throws Exception {
        var mvc = MockMvcBuilders.standaloneSetup(new UserCenterController(service)).build();
        var card = new BankCard(11, 7, "招商银行", "储蓄卡", "**** **** **** 0123", 1, 1, "2026-10-08 12:00:00");
        when(service.addBankCard(7, "招商银行", "储蓄卡", "0123")).thenReturn(card);

        mvc.perform(post("/api/wallet/bank-cards").requestAttr("userId", 7L)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":99,\"bankName\":\"招商银行\",\"cardType\":\"储蓄卡\",\"cardNoLast4\":\"0123\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.data.userId").value(7)).andExpect(jsonPath("$.data.isDefault").value(1))
                .andExpect(jsonPath("$.data.cardNoMasked").value("**** **** **** 0123"))
                .andExpect(jsonPath("$.data.cardNoLast4").doesNotExist());
        verify(service).addBankCard(7, "招商银行", "储蓄卡", "0123");
    }

    @Test
    void deleteUsesAuthenticatedAccountAndReturnsEmptySuccess() throws Exception {
        var mvc = MockMvcBuilders.standaloneSetup(new UserCenterController(service)).build();

        mvc.perform(delete("/api/wallet/bank-cards/11").requestAttr("userId", 7L).param("userId", "99"))
                .andExpect(status().isOk()).andExpect(content().json("{\"code\":200,\"message\":\"success\",\"data\":null}"));
        verify(service).deleteBankCard(7, 11);
    }

    @Test
    void missingAuthenticatedIdentityNeverInvokesService() throws Exception {
        var mvc = MockMvcBuilders.standaloneSetup(new UserCenterController(service)).build();

        mvc.perform(delete("/api/wallet/bank-cards/11")).andExpect(status().isBadRequest());
        verifyNoInteractions(service);
    }

    @Test
    void fullNumberAddReturnsMaskedContractAndRevealedResponseIsNotCacheable() throws Exception {
        var mvc = MockMvcBuilders.standaloneSetup(new UserCenterController(service)).build();
        String number = "6225888888880123";
        var card = new BankCard(11, 7, "招商银行", "储蓄卡", "**** **** **** 0123", 1, 1, "now");
        when(service.addBankCardFull(7, "招商银行", "储蓄卡", number)).thenReturn(card);
        when(service.revealBankCard(7, 11, "135790")).thenReturn(number);
        mvc.perform(post("/api/wallet/bank-cards").requestAttr("userId", 7L)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"bankName\":\"招商银行\",\"cardType\":\"储蓄卡\",\"fullCardNumber\":\"" + number + "\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.fullCardNumber").doesNotExist())
                .andExpect(jsonPath("$.data.cardNoMasked").value("**** **** **** 0123"));
        mvc.perform(post("/api/wallet/bank-cards/11/reveal").requestAttr("userId", 7L)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"paymentPassword\":\"135790\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.cardNumber").value(number))
                .andExpect(header().string("Cache-Control", "no-store"));
    }

    @Test
    void malformedCardBodyIsFixedErrorAndWrongPinOnlyIsCounted() throws Exception {
        var limiter = mock(LoginRateLimiter.class);
        var mvc = MockMvcBuilders.standaloneSetup(new UserCenterController(service, limiter))
                .setControllerAdvice(new com.example.takeout.common.GlobalExceptionHandler()).build();
        mvc.perform(post("/api/wallet/bank-cards").requestAttr("userId", 7L)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"fullCardNumber\": [\"6225888888880123\"]}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value("请求参数格式不正确"));
        when(service.revealBankCard(7, 11, "135790")).thenThrow(new BizException("该银行卡未录入完整卡号，请重新添加"));
        mvc.perform(post("/api/wallet/bank-cards/11/reveal").requestAttr("userId", 7L)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"paymentPassword\":\"135790\"}"))
                .andExpect(status().isBadRequest());
        verify(limiter, never()).recordAttempt("bank-card-reveal", "7:127.0.0.1");
    }
}
