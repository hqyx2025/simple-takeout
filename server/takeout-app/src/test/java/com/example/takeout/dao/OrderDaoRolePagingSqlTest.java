package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderDaoRolePagingSqlTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final OrderDao dao = new OrderDao(jdbc);

    @Test
    void userPageFiltersByOwnerAndOptionalStatus() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listByUser(9, 4, 30, 60L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), args.capture());
        assertTrue(sql.getValue().endsWith("WHERE user_id = ? AND status = ? ORDER BY id DESC LIMIT ? OFFSET ?"));
        assertEquals(9L, args.getValue()[0]);
        assertEquals(4, args.getValue()[1]);
        assertEquals(30, args.getValue()[2]);
        assertEquals(60L, args.getValue()[3]);
    }

    @Test
    void merchantPageUsesOwnerOrEmployeeAccessExcludesUnpaidAndJoinsRiderInOneQuery() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listByMerchant(17, 2, 30, 90L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), args.capture());
        assertTrue(sql.getValue().contains("JOIN stores s ON s.id = o.store_id"));
        assertTrue(sql.getValue().contains("LEFT JOIN riders r ON r.id = o.rider_id"));
        assertTrue(sql.getValue().contains("s.owner_id = ? OR EXISTS"));
        assertTrue(sql.getValue().contains("e.user_id = ? AND e.status = 1"));
        assertTrue(sql.getValue().contains("AND o.status <> 0 AND o.status = ?"));
        assertTrue(sql.getValue().endsWith("ORDER BY o.id DESC LIMIT ? OFFSET ?"));
        assertEquals(17L, args.getValue()[0]);
        assertEquals(17L, args.getValue()[1]);
        assertEquals(2, args.getValue()[2]);
        assertEquals(30, args.getValue()[3]);
        assertEquals(90L, args.getValue()[4]);
    }

    @Test
    void riderPageKeepsActiveOrdersAheadOfCompletedHistory() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listByRider(5, 30, 0L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), any(Object[].class));
        assertTrue(sql.getValue().contains("CASE WHEN status IN (2,3) THEN 0 ELSE 1 END"));
        assertTrue(sql.getValue().contains("CASE WHEN status IN (2,3) THEN (CASE WHEN DATE_FORMAT(ready_time_dt"));
        assertTrue(sql.getValue().contains("CASE WHEN status NOT IN (2,3) THEN (CASE WHEN DATE_FORMAT(complete_time_dt"));
        assertTrue(sql.getValue().endsWith("id DESC LIMIT ? OFFSET ?"));
    }

    @Test
    void expiredPendingParsesLegacyTimeAndBindsDatetimeDeadlineExplicitly() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listExpiredPending("2026-10-14 10:00:00");

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), args.capture());
        assertTrue(sql.getValue().contains("CASE WHEN DATE_FORMAT(create_time_dt,"));
        assertTrue(sql.getValue().contains("STR_TO_DATE(create_time,"));
        assertTrue(sql.getValue().contains("< STR_TO_DATE(NULLIF(?, ''),"));
        assertFalse(sql.getValue().contains("create_time < ?"));
        assertEquals("2026-10-14 10:00:00", args.getValue()[0]);
    }

    @Test
    void userCountUsesTheSameOwnerAndStatusFilter() {
        when(jdbc.queryForObject(anyString(), eq(Integer.class), eq(9L), eq(4))).thenReturn(61);

        assertEquals(61, dao.countByUser(9, 4));

        verify(jdbc).queryForObject("SELECT COUNT(*) FROM orders WHERE user_id = ? AND status = ?",
                Integer.class, 9L, 4);
    }
}
