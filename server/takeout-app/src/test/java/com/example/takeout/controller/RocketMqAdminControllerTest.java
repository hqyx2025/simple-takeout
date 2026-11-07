package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.service.mq.RocketMqOperations;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class RocketMqAdminControllerTest {
    private final RocketMqOperations operations = mock(RocketMqOperations.class);
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private RocketMqAdminController controller;

    @BeforeEach @SuppressWarnings("unchecked") void open() {
        ObjectProvider<RocketMqOperations> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(operations);
        controller = new RocketMqAdminController(provider, jdbc);
    }

    @Test void otherRolesCannotReadOrReplayAnotherDomainsMessages() {
        for (int role : new int[]{0, 1, 3}) {
            assertThrows(BizException.class, () -> controller.status(role));
            assertThrows(BizException.class, () -> controller.replay(role, 7, 10));
        }
        verifyNoInteractions(operations, jdbc);
    }

    @Test void replayHasBoundedInputAndAuditTrail() throws Exception {
        assertThrows(BizException.class, () -> controller.replay(2, 7, 0));
        assertThrows(BizException.class, () -> controller.replay(2, 7, 11));
        verifyNoInteractions(operations, jdbc);
        when(operations.replayDeadLetters(10)).thenReturn(2);
        assertNotNull(controller.replay(2, 7, 10));
        verify(operations).replayDeadLetters(10);
        verify(jdbc).update(contains("'MQ_DLQ_REPLAY'"), eq(7L), anyLong());
    }
}
