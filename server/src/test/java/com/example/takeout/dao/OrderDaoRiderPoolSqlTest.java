package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 骑手待取餐池的 SQL 契约测试。
 *
 * <p>为什么单独钉 SQL：骑手整条链最脆弱的一环是「订单要满足什么条件才会出现在抢单池」和
 * 「商家出餐到底写不写 ready_time」。这两件事完全由 SQL 决定，用 Mockito 替换 DAO 的
 * 业务层测试**抓不到**这类回归——把 markReady 改成同时把 status 推到 3，业务层测试依旧全绿，
 * 但真实数据再也进不了池子，骑手端永远空列表。所以这里直接断言 SQL 文本与筛选条件。
 */
class OrderDaoRiderPoolSqlTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final OrderDao dao = new OrderDao(jdbc);

    @SuppressWarnings("unchecked")
    private String captureQuerySql() {
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class));
        return sql.getValue();
    }

    @Test
    void riderPoolOnlySelectsReadyUnassignedCookingOrders() {
        when(jdbc.query(anyString(), any(RowMapper.class))).thenReturn(java.util.List.of());

        dao.listRiderPool();

        String sql = captureQuerySql();
        // 池子的三个条件缺一不可：制作中(2) + 已出餐(ready_time 非空) + 未分配骑手(rider_id=0)
        assertTrue(sql.contains("status = 2"), "池子必须只取制作中的订单：" + sql);
        assertTrue(sql.contains("ready_time <> ''"), "池子必须只取商家已出餐的订单：" + sql);
        assertTrue(sql.contains("rider_id = 0"), "池子必须只取尚未被接走的订单：" + sql);
        // 关键回归点：出餐后状态若被改成 3，这条筛查会把订单永久排除在池外
        assertFalse(sql.contains("status = 3"), "池子不能要求 status=3：" + sql);
    }

    @Test
    void markReadyWritesReadyTimeWithoutChangingStatus() {
        when(jdbc.update(anyString(), anyString(), any(Long.class))).thenReturn(1);

        assertTrue(dao.markReady(500L, "2026-09-15 10:05:00"));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), anyString(), any(Long.class));
        String statement = sql.getValue();
        // 只写 ready_time：把 status 一起改掉会让订单跳出池子的 status = 2 筛选
        assertTrue(statement.contains("ready_time = ?"), statement);
        assertFalse(statement.contains("status = 3"), "出餐不得把订单推进到配送中：" + statement);
        assertTrue(statement.contains("ready_time = ''"), "重复出餐必须被条件更新挡住：" + statement);
    }

    @Test
    void grabRequiresReadyUnassignedCookingOrder() {
        when(jdbc.update(anyString(), any(Long.class), any(Long.class))).thenReturn(1);

        assertTrue(dao.tryAssignRider(500L, 77L));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), any(Long.class), any(Long.class));
        String statement = sql.getValue();
        // 抢单必须绑定骑手，且只能抢「已出餐 + 还没人接」的订单
        assertTrue(statement.contains("rider_id = ?"), statement);
        assertTrue(statement.contains("rider_id = 0"), statement);
        assertTrue(statement.contains("status = 2"), statement);
        assertTrue(statement.contains("ready_time <> ''"), statement);
    }

    @Test
    void grabFailsWhenConditionUpdateMatchesNothing() {
        when(jdbc.update(anyString(), any(Long.class), any(Long.class))).thenReturn(0);

        // 0 行 = 订单已被别人抢走 / 商家还没出餐：必须返回 false 让 service 报错
        assertFalse(dao.tryAssignRider(500L, 77L));
    }

    @Test
    void riderDeliverOnlyMatchesOwnDelivery() {
        when(jdbc.update(anyString(), anyString(), any(Long.class), any(Long.class))).thenReturn(1);

        assertTrue(dao.riderDeliver(500L, 77L, "2026-09-15 10:20:00"));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), anyString(), any(Long.class), any(Long.class));
        String statement = sql.getValue();
        // 只能送达「本人配送中」的订单，并且仍然要求 status = 3
        assertTrue(statement.contains("rider_id = ?"), statement);
        assertTrue(statement.contains("status = 3"), statement);
        assertEquals(3, statement.split("\\?", -1).length - 1, "参数个数必须与占位符一致：" + statement);
    }
}
