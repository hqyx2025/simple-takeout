package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class StoreDaoDispatchTest {
    @Test
    void dispatchRangeReadDoesNotAggregateOrderSales() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(), any(RowMapper.class), eq(31L))).thenReturn(List.of());
        assertTrue(new StoreDao(jdbc).findForDispatch(31L).isEmpty());
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), eq(31L));
        assertTrue(sql.getValue().contains("s.id = ?"));
        assertFalse(sql.getValue().contains("orders"));
        assertFalse(sql.getValue().contains("GROUP BY"));
    }
}
