package com.example.takeout.controller;

import com.example.takeout.common.GlobalExceptionHandler;
import com.example.takeout.service.AfterSalesService;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.util.List;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class AfterSalesControllerTest {
    private final AfterSalesService service = mock(AfterSalesService.class);
    private final org.springframework.test.web.servlet.MockMvc mvc = MockMvcBuilders
            .standaloneSetup(new AfterSalesController(service)).setControllerAdvice(new GlobalExceptionHandler()).build();

    @Test
    void merchantEndpointsUseAuthenticatedMerchantAndRejectOtherRoles() throws Exception {
        for (int role : new int[]{0, 2, 3}) {
            mvc.perform(get("/api/merchant/orders/7/refunds").requestAttr("userId", 4L).requestAttr("role", role))
                    .andExpect(status().isForbidden());
            mvc.perform(get("/api/merchant/after-sales/ledger").requestAttr("userId", 4L).requestAttr("role", role))
                    .andExpect(status().isForbidden());
            mvc.perform(post("/api/after-sales/9/merchant-evidence").requestAttr("userId", 4L).requestAttr("role", role)
                            .contentType("application/json").content("{}"))
                    .andExpect(status().isForbidden());
        }
        verifyNoInteractions(service);
        mvc.perform(get("/api/merchant/orders/7/refunds").requestAttr("userId", 4L).requestAttr("role", 1))
                .andExpect(status().isOk());
        verify(service).merchantHistory(4, 7);
        mvc.perform(post("/api/after-sales/9/merchant-evidence").requestAttr("userId", 4L).requestAttr("role", 1)
                        .contentType("application/json")
                        .content("{\"merchantId\":99,\"response\":\"已核查\",\"evidenceImages\":[\"/uploads/store.jpg\"]}"))
                .andExpect(status().isOk());
        verify(service).merchantEvidence(4, 9, "已核查", List.of("/uploads/store.jpg"));
    }
}
