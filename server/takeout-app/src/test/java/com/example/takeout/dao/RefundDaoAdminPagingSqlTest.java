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

class RefundDaoAdminPagingSqlTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final RefundDao dao = new RefundDao(jdbc);

    @Test
    void statusListIsPagedInDatabase() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listForAdmin("PENDING", 50, 100L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), args.capture());
        assertTrue(sql.getValue().endsWith("WHERE status = ? ORDER BY id DESC LIMIT ? OFFSET ?"));
        assertEquals("PENDING", args.getValue()[0]);
        assertEquals(50, args.getValue()[1]);
        assertEquals(100L, args.getValue()[2]);
    }

    @Test
    void countUsesOptionalStatus() {
        when(jdbc.queryForObject(anyString(), eq(Integer.class), eq("PENDING"))).thenReturn(8);

        assertEquals(8, dao.countForAdmin("PENDING"));

        verify(jdbc).queryForObject("SELECT COUNT(*) FROM refund_records WHERE status = ?", Integer.class, "PENDING");
    }
}
