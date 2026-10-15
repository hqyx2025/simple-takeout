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

class UserDaoAdminPagingSqlTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final UserDao dao = new UserDao(jdbc);

    @Test
    void pageQueryUsesSameFiltersAndDatabaseLimit() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listForAdmin(1, 0, "food", 25, 50);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), args.capture());
        assertTrue(sql.getValue().endsWith("ORDER BY u.id DESC LIMIT ? OFFSET ?"));
        assertTrue(sql.getValue().contains("u.role <> 2 AND u.role = ? AND u.status = ?"));
        Object[] values = args.getValue();
        assertEquals(1, values[0]);
        assertEquals(0, values[1]);
        assertEquals("%food%", values[2]);
        assertEquals("%food%", values[3]);
        assertEquals(25, values[4]);
        assertEquals(50L, values[5]);
    }

    @Test
    void countQueryFiltersOutAdminsAndUsesTheSameSearchCriteria() {
        when(jdbc.queryForObject(anyString(), eq(Integer.class), any(Object[].class))).thenReturn(17);

        int total = dao.countForAdmin(null, 1, "138");

        assertEquals(17, total);
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).queryForObject(sql.capture(), eq(Integer.class), args.capture());
        assertTrue(sql.getValue().contains("COUNT(*) FROM users u WHERE u.role <> 2 AND u.status = ?"));
        assertEquals(1, args.getValue()[0]);
        assertEquals("%138%", args.getValue()[1]);
        assertEquals("%138%", args.getValue()[2]);
    }
}
