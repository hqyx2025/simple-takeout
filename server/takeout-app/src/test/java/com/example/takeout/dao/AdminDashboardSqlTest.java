package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** 近30天榜排除未支付/取消/全退，申请中和部分退款仍计订单。 */
class AdminDashboardSqlTest {

    @Test
    void topStoresUsesRealPaidOrdersInLastThirtyDays() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(), any(org.springframework.jdbc.core.RowMapper.class), any(Object[].class)))
                .thenReturn(java.util.List.of());
        AdminStatsDao dao = new AdminStatsDao(jdbc);

        dao.topStores(10);

        org.mockito.ArgumentCaptor<String> sql = org.mockito.ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(), any(org.springframework.jdbc.core.RowMapper.class), any(Object[].class));
        assertTrue(sql.getValue().contains("o.status IN (1,2,3,4,6) AND o.escrow_status <> 2"), sql.getValue());
        assertTrue(sql.getValue().contains("INTERVAL 30 DAY"), sql.getValue());
        assertTrue(sql.getValue().contains("o.pay_time_dt"), sql.getValue());
        assertTrue(sql.getValue().contains("o.pay_amount - COALESCE(refunds.refunded_amount, 0)"), sql.getValue());
    }
}
