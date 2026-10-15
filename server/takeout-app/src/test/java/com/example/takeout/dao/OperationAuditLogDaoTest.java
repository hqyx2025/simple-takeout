package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OperationAuditLogDaoTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final OperationAuditLogDao dao = new OperationAuditLogDao(jdbc);

    @Test
    void insertsActorOrderAndResultMetadata() {
        dao.insert(8, 3, 12, 3, "RiderController.pickup", "PUT", "/api/rider/orders/12/pickup",
                "SUCCESS", 200, "trace-1", 1000);

        verify(jdbc).update("INSERT INTO operation_audit_logs(operator_id, operator_role, order_id, status_after, action, " +
                        "http_method, request_path, outcome, http_status, trace_id, created_at) " +
                        "VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                8L, 3, 12L, 3, "RiderController.pickup", "PUT", "/api/rider/orders/12/pickup",
                "SUCCESS", 200, "trace-1", 1000L);
    }

    @Test
    void listUsesNewestFirstDatabasePagination() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.list(50, 100L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), args.capture());
        assertTrue(sql.getValue().endsWith("ORDER BY id DESC LIMIT ? OFFSET ?"));
        assertEquals(50, args.getValue()[0]);
        assertEquals(100L, args.getValue()[1]);
    }

    @Test
    void readsOrderStatusAfterTheRequestCompleted() {
        when(jdbc.queryForObject("SELECT status FROM orders WHERE id = ?", Integer.class, 12L)).thenReturn(3);

        assertEquals(3, dao.currentOrderStatus(12));

        verify(jdbc).queryForObject("SELECT status FROM orders WHERE id = ?", Integer.class, 12L);
    }
}
