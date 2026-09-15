package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 平台统计口径的 SQL 契约测试。
 *
 * <p>为什么单独钉 SQL：这一页的缺陷形态是「两个数字口径不一致」，而它完全由 SQL 决定。
 * 历史缺陷是 today_orders 统计了全部状态、today_gmv 却排除 5/6，于是同屏出现
 * 「今日订单：10」和「今日成交：¥0.00」——看着像系统算错了，其实是两个字段各按各的口径查。
 * 近7日趋势的 order_count 是同一个漏网字段（用 COUNT(*) 数了全部状态）。
 *
 * <p>口径：**订单数与成交额必须同时排除已取消(5)与退款中(6)**。
 * 唯一的例外是 total_orders，它是「累计下单数」的展示口径，故意含全部状态。
 */
class AdminStatsDaoSqlTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final AdminStatsDao dao = new AdminStatsDao(jdbc);

    /** overview 需要聚合行非空才能走完（DAO 会解引用它），用全零替身即可。 */
    private static final com.example.takeout.model.AdminStatistics EMPTY =
            new com.example.takeout.model.AdminStatistics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, java.util.List.of());

    /** 抓 overview 里那条大 SELECT（第一个参数即 SQL 文本）。 */
    private String captureOverviewSql() {
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).queryForObject(sql.capture(), any(RowMapper.class), anyString(), anyString());
        return sql.getValue();
    }

    private String captureTrendSql() {
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), anyString());
        return sql.getValue();
    }

    @Test
    void todayOrdersAndTodayGmvShareTheSameStatusFilter() {
        when(jdbc.queryForObject(anyString(), any(RowMapper.class), anyString(), anyString())).thenReturn(EMPTY);
        when(jdbc.query(anyString(), any(RowMapper.class), any(Long.class))).thenReturn(java.util.List.of());

        dao.overview(10);

        String sql = captureOverviewSql();
        assertTrue(sql.contains("AS today_orders"), "找不到 today_orders 字段：" + sql);
        // 关键回归点：today_orders 必须带排除条件，否则与 today_gmv 口径不一致
        String ordersClause = sql.substring(sql.indexOf("AS today_orders") - 120, sql.indexOf("AS today_orders"));
        assertTrue(ordersClause.contains("status NOT IN (5,6)"),
                "today_orders 必须与 today_gmv 一样排除已取消/退款中订单：" + ordersClause);
        assertTrue(sql.contains("status NOT IN (5,6)), 0) AS today_gmv"),
                "today_gmv 的排除条件被改动：" + sql);
    }

    @Test
    void trendOrderCountExcludesCancelledAndRefunding() {
        when(jdbc.query(anyString(), any(RowMapper.class), anyString())).thenReturn(java.util.List.of());

        dao.orderTrend(7);

        String sql = captureTrendSql();
        // 关键回归点：不能用 COUNT(*) 把已取消订单也数进趋势柱状图
        assertTrue(sql.contains("COUNT(CASE WHEN status NOT IN (5,6) THEN 1 END) AS order_count"),
                "趋势的 order_count 必须排除已取消/退款中订单：" + sql);
    }

    @Test
    void totalOrdersKeepsAllStatusesOnPurpose() {
        when(jdbc.queryForObject(anyString(), any(RowMapper.class), anyString(), anyString())).thenReturn(EMPTY);
        when(jdbc.query(anyString(), any(RowMapper.class), any(Long.class))).thenReturn(java.util.List.of());

        dao.overview(10);

        String sql = captureOverviewSql();
        // total_orders 是「累计下单数」，故意含全部状态，别顺手改成排除
        assertTrue(sql.contains("(SELECT COUNT(*) FROM orders) AS total_orders"),
                "total_orders 应保持累计下单数口径（含全部状态）：" + sql);
    }
}
