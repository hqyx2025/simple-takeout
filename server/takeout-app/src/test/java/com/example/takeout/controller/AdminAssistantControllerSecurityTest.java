package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.service.AssistantAiClient;
import com.example.takeout.service.AssistantConfigService;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class AdminAssistantControllerSecurityTest {
    private final AssistantConfigService configs = mock(AssistantConfigService.class);
    private final AssistantAiClient client = mock(AssistantAiClient.class);
    private final AdminAssistantController controller = new AdminAssistantController(configs, client);

    @Test
    void allNonAdminRolesCannotReadWriteOrTestConfiguration() {
        for (int role : new int[]{0, 1, 3, -1, 4}) {
            assertEquals(403, assertThrows(BizException.class, () -> controller.config(role)).getCode());
            assertEquals(403, assertThrows(BizException.class, () -> controller.save(role,
                    new AssistantConfigService.SaveRequest(false, "", "", "", false))).getCode());
            assertEquals(403, assertThrows(BizException.class, () -> controller.test(role)).getCode());
        }
        verifyNoInteractions(configs, client);
    }

    @Test
    void adminOnlyReceivesSafeConfigurationView() {
        var view = new AssistantConfigService.View(true, "https://api.example.com/v1/chat/completions", "model", true);
        var request = new AssistantConfigService.SaveRequest(true, view.endpoint(), view.model(), "", false);
        when(configs.view()).thenReturn(view);
        when(configs.save(request)).thenReturn(view);

        assertEquals(view, controller.config(2).data());
        assertEquals(view, controller.save(2, request).data());
        verifyNoInteractions(client);
    }

    @Test
    void connectionTestUsesStoredCredentialsAndReturnsFixedSuccessText() {
        var config = new AssistantConfigService.Config(false, "https://api.example.com/v1/chat/completions", "model", "sk-secret");
        when(configs.load()).thenReturn(config);
        when(client.complete(config, "请回复连接成功", List.of())).thenReturn("arbitrary upstream content");

        assertEquals("连接成功", controller.test(2).data());
        verify(client).complete(config, "请回复连接成功", List.of());
    }

    @Test
    void malformedKeyJsonUsesLocalHandlerWithoutExposingParserError() throws Exception {
        var localController = spy(controller);
        var mvc = MockMvcBuilders.standaloneSetup(localController)
                .setControllerAdvice(new com.example.takeout.common.GlobalExceptionHandler()).build();
        mvc.perform(put("/api/admin/assistant/config")
                        .requestAttr("role", 2).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":false,\"apiKey\":sk-private-unquoted}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().json("{\"code\":400,\"message\":\"请求参数格式不正确\",\"data\":null}"));

        verify(localController).invalidBody();
        verifyNoInteractions(configs, client);
    }
}
