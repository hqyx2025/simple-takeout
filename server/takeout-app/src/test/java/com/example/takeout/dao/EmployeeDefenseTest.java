package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.mockito.Mockito.*;
import static org.junit.jupiter.api.Assertions.*;

class EmployeeDefenseTest {
    @Test void deletionIsScopedToTheAuthorizedStoreAndReportsNoMatch() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        String sql = "DELETE FROM employees WHERE id = ? AND store_id = ?";
        EmployeeDao employees = new EmployeeDao(jdbc);
        assertFalse(employees.delete(10, 999));
        when(jdbc.update(sql, 12L, 10L)).thenReturn(1);
        assertTrue(employees.delete(10, 12));
        verify(jdbc).update(sql, 999L, 10L);
        verify(jdbc).update(sql, 12L, 10L);
    }
}
