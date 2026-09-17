package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** 数据大屏 SQL 契约：店铺成交额排行必须排除已取消(5)/退款中(6)，与平台统计口径一致。 */
class AdminDashboardSqlTest {

    @Test
    void topStoresExcludesCancelledAndRefunding() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(), any(org.springframework.jdbc.core.RowMapper.class), any(Object[].class)))
                .thenReturn(java.util.List.of());
        AdminStatsDao dao = new AdminStatsDao(jdbc);

        dao.topStores(10);

        org.mockito.ArgumentCaptor<String> sql = org.mockito.ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(), any(org.springframework.jdbc.core.RowMapper.class), any(Object[].class));
        assertTrue(sql.getValue().contains("o.status NOT IN (5,6)"), sql.getValue());
    }
}
