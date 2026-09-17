package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** 套餐查询 SQL 契约：用户浏览只返上架套餐（AND status = 1），商户全量不含该过滤。 */
class SetmealSqlTest {

    @Test
    void activeOnlyAppendsStatusFilter() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        StoreDao dao = new StoreDao(jdbc);
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listSetmealsByStore(10, true);
        dao.listSetmealsByStore(10, false);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc, times(2)).query(sql.capture(), any(RowMapper.class), any(Object[].class));
        assertTrue(sql.getAllValues().get(0).contains("AND status = 1"), sql.getAllValues().get(0));
        assertFalse(sql.getAllValues().get(1).contains("AND status = 1"), sql.getAllValues().get(1));
    }
}
