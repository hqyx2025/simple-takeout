package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.OperationAuditLogDao;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminOperationLogControllerTest {

    @Test
    void onlyAdminCanReadPagedAuditLogs() {
        var controller = new AdminOperationLogController(mock(OperationAuditLogDao.class));

        BizException error = assertThrows(BizException.class, () -> controller.list(1, 1, 50));

        assertEquals(403, error.getCode());
    }

    @Test
    void clampsPageSizeAndReturnsPaginationMetadata() {
        var dao = mock(OperationAuditLogDao.class);
        when(dao.count()).thenReturn(220);
        when(dao.list(100, 100)).thenReturn(List.of());
        var controller = new AdminOperationLogController(dao);

        var response = controller.list(2, 2, 500).data();

        assertEquals(220, response.total());
        assertEquals(2, response.page());
        assertEquals(100, response.pageSize());
        assertEquals(true, response.hasMore());
        verify(dao).list(100, 100);
    }
}
