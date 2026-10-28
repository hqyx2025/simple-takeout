package com.example.takeout.dao;

import com.example.takeout.model.AdminStatistics;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class AdminStatsDaoSqlTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final AdminStatsDao dao = new AdminStatsDao(jdbc);
    private static final AdminStatistics EMPTY = new AdminStatistics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, List.of());

    @Test
    void overviewUsesPaidOrdersAndSuccessfulRefundsWithoutDroppingPendingAfterSales() {
        when(jdbc.queryForObject(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(EMPTY);
        dao.overview(10);
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).queryForObject(sql.capture(), any(RowMapper.class), any(Object[].class));
        String query = sql.getValue();
        assertTrue(query.contains("COUNT(*) AS total_orders"));
        assertFalse(query.contains("WHERE o.status"), "累计下单数不能被状态筛选缩小");
        assertTrue(query.contains("o.status IN (1,2,3,4,6) AND o.escrow_status <> 2"));
        assertTrue(query.contains("DATE_FORMAT(o.pay_time_dt,"));
        assertTrue(query.contains("STR_TO_DATE(o.pay_time,"));
        assertFalse(query.contains("create_time"));
        assertTrue(query.contains("o.pay_amount - COALESCE(refunds.refunded_amount, 0)"));
        assertTrue(query.contains("WHERE status = 'REFUNDED' GROUP BY order_id"));
        assertTrue(query.contains("o.escrow_status = 1 OR settlement.order_id IS NOT NULL"));
        String orderWindow = query.substring(query.lastIndexOf("COALESCE(SUM(CASE WHEN", query.indexOf("AS today_orders")), query.indexOf(" THEN 1 ELSE 0 END), 0) AS today_orders"));
        String gmvWindow = query.substring(query.lastIndexOf("COALESCE(SUM(CASE WHEN", query.indexOf("AS today_gmv")), query.indexOf(" THEN GREATEST", query.indexOf("AS today_orders")));
        assertEquals(orderWindow, gmvWindow);

        ArgumentCaptor<String> hot = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(hot.capture(), any(RowMapper.class), args.capture());
        assertTrue(hot.getValue().contains("SUM(oi.quantity)"));
        assertFalse(hot.getValue().contains("g.sales"));
        assertEquals(args.getValue()[0], args.getValue()[1]);
        assertEquals(10, args.getValue()[2]);
    }

    @Test
    void trendUsesPaymentDayAndBoundsFutureDates() {
        dao.orderTrend(7);
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), args.capture());
        assertTrue(sql.getValue().contains("COUNT(*) AS order_count"));
        assertTrue(sql.getValue().contains("WHERE o.status IN (1,2,3,4,6) AND o.escrow_status <> 2"));
        assertTrue(sql.getValue().contains("o.pay_time_dt"));
        assertFalse(sql.getValue().contains("create_time"));
        assertEquals(2, args.getValue().length);
        assertEquals(7, java.time.temporal.ChronoUnit.DAYS.between(java.time.LocalDate.parse((String) args.getValue()[0]), java.time.LocalDate.parse((String) args.getValue()[1])));
    }
}
