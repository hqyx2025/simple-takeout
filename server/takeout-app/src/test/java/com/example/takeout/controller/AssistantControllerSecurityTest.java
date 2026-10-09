package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.service.AssistantService;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AssistantControllerSecurityTest {
    @Test
    void otherRolesCannotUsePersonalAssistant() {
        AssistantService service = mock(AssistantService.class);
        AssistantController controller = new AssistantController(service);
        for (int role : List.of(1, 2, 3)) {
            BizException error = assertThrows(BizException.class, () -> controller.chat(9, role,
                    new AssistantController.AskRequest("我的订单", List.of())));
            assertEquals(403, error.getCode());
        }
        verifyNoInteractions(service);
    }

    @Test
    void customerRequestUsesAuthenticatedUserAndHistory() {
        AssistantService service = mock(AssistantService.class);
        AssistantController controller = new AssistantController(service);
        when(service.reply(9, "问题", List.of())).thenReturn(new AssistantService.AssistantReply("回答", List.of()));
        assertEquals("回答", controller.chat(9, 0,
                new AssistantController.AskRequest("问题", List.of())).data().answer());
        verify(service).reply(9, "问题", List.of());
    }
}
