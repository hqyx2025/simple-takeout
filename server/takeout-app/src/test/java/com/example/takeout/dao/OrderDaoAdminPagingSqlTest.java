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

class OrderDaoAdminPagingSqlTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final OrderDao dao = new OrderDao(jdbc);

    @Test
    void statusPageUsesDatabaseLimitAndOffset() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listForAdmin(3, 25, 50L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), args.capture());
        assertTrue(sql.getValue().endsWith("WHERE status = ? ORDER BY id DESC LIMIT ? OFFSET ?"));
        assertEquals(3, args.getValue()[0]);
        assertEquals(25, args.getValue()[1]);
        assertEquals(50L, args.getValue()[2]);
    }

    @Test
    void countUsesTheOptionalStatusFilter() {
        when(jdbc.queryForObject(anyString(), eq(Integer.class), eq(3))).thenReturn(31);

        assertEquals(31, dao.countForAdmin(3));

        verify(jdbc).queryForObject("SELECT COUNT(*) FROM orders WHERE status = ?", Integer.class, 3);
    }

    @Test
    void adminRowsJoinRiderDataWithinThePageQuery() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listForAdminWithRider(3, 25, 50L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), any(Object[].class));
        assertTrue(sql.getValue().contains("LEFT JOIN riders r ON r.id = o.rider_id"));
        assertTrue(sql.getValue().endsWith("WHERE o.status = ? ORDER BY o.id DESC LIMIT ? OFFSET ?"));
    }
}
