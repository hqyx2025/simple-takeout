package com.example.takeout.dao;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Outbox 多实例认领的 SQL 契约测试。
 *
 * <p>为什么单独钉 SQL：多实例下「同一事件被两个实例同时搬运」这件事完全由 SQL 决定，
 * 用业务层测试（把 DAO 换掉）抓不到。</p>
 *
 * <p>两个必须同时成立的条件：</p>
 * <ul>
 *   <li>{@code FOR UPDATE SKIP LOCKED}：实例 A 锁住的行，实例 B 直接跳过而不是排队等待，
 *       否则中继扫描会退化成串行、吞吐随实例数下降。</li>
 *   <li>{@code lease_until < now} 租约判据：认领过但处理中途崩溃的行，只能在租约过期后
 *       被重新认领；少了这一条，崩溃即造成事件永久滞留。</li>
 * </ul>
 * 另外 {@code markRetry} 必须释放租约，否则投递失败的事件要干等租约到期才能重试。
 */
class OutboxEventDaoClaimSqlTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final TransactionTemplate tx = mock(TransactionTemplate.class);
    private final OutboxEventDao dao = new OutboxEventDao(jdbc, tx);

    @BeforeEach
    void runCallbackInline() {
        // TransactionTemplate 在测试里同步执行回调，等价于「事务内」的一次调用
        when(tx.execute(any(TransactionCallback.class))).thenAnswer(inv -> {
            TransactionCallback<?> callback = inv.getArgument(0);
            return callback.doInTransaction(mock(TransactionStatus.class));
        });
    }

    @SuppressWarnings("unchecked")
    @Test
    void claimUsesSkipLockedAndLeasePredicate() {
        when(jdbc.query(anyString(), any(RowMapper.class), anyLong(), anyInt())).thenReturn(List.of());

        dao.claimPending(100, "instance-a", 1_700_000_000_000L, 1_700_000_060_000L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), anyLong(), anyInt());
        String statement = sql.getValue();

        assertTrue(statement.contains("FOR UPDATE SKIP LOCKED"),
                "认领必须用 SKIP LOCKED 跳过其他实例已锁住的行，否则多实例互相阻塞：" + statement);
        assertTrue(statement.contains("status = 0"), "只认领未投递事件：" + statement);
        assertTrue(statement.contains("lease_until < ?"), "必须按租约过期筛选，崩溃后的行才能被重新认领：" + statement);
        assertFalse(statement.contains("WHERE status = 0 ORDER BY id LIMIT"),
                "禁用旧的「无锁全量扫描」写法，正是它导致多实例重复搬运：" + statement);
    }

    @Test
    void claimStampsOwnerAndLeaseOnClaimedRows() {
        OutboxEventDao.OutboxEvent claimed =
                new OutboxEventDao.OutboxEvent(7L, "ORDER_PAID", 42L, "{}", 0, 0, "2026-09-18 15:00:00");
        when(jdbc.query(anyString(), any(RowMapper.class), anyLong(), anyInt())).thenReturn(List.of(claimed));

        List<OutboxEventDao.OutboxEvent> result = dao.claimPending(100, "instance-a", 1000L, 2000L);

        assertEquals(1, result.size(), "认领到的事件必须原样返回给中继投递");
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).batchUpdate(sql.capture(), anyList());
        String statement = sql.getValue();
        assertTrue(statement.contains("owner = ?"), "必须写入认领者，便于诊断「谁搬走了这条事件」：" + statement);
        assertTrue(statement.contains("lease_until = ?"), "必须写入租约到期时间，崩溃后据此重新认领：" + statement);
    }

    @Test
    void claimReturnsEmptyWithoutUpdatingWhenNothingToClaim() {
        when(jdbc.query(anyString(), any(RowMapper.class), anyLong(), anyInt())).thenReturn(List.of());

        assertTrue(dao.claimPending(100, "instance-a", 1000L, 2000L).isEmpty());

        // 没有可认领的行时不应产生任何 UPDATE，避免多实例下空转写库
        verify(jdbc, org.mockito.Mockito.never()).batchUpdate(anyString(), anyList());
    }

    @Test
    void markRetryReleasesLeaseSoAnyInstanceCanRetry() {
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);

        dao.markRetry(7L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), any(Object[].class));
        String statement = sql.getValue();
        assertTrue(statement.contains("retry_count = retry_count + 1"), statement);
        // 释放租约：否则投递失败的事件要干等租约到期，其他实例也帮不上忙
        assertTrue(statement.contains("lease_until = 0"), "重试必须释放租约：" + statement);
    }

    @Test
    void markSentKeepsRowOutOfFutureClaims() {
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);

        dao.markSent(7L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), any(Object[].class));
        assertTrue(sql.getValue().contains("status = 1"), "投递成功后置为已投递，永不再被认领：" + sql.getValue());
    }
}