package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 秒杀「一人一单」SQL 契约：防重的唯一权威是 seckill_orders 的唯一键 (user_id, seckill_id)，
 * Dao 用 INSERT IGNORE 依赖它、用 DELETE 释放资格。这里钉住两条 SQL 的形状，防止有人
 * 把 INSERT IGNORE 改成普通 INSERT——那样跨单重复会变成 MySQL 500，而非可读的「每人限购一次」。
 */
class SeckillOnePerUserSqlTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final SeckillDao dao = new SeckillDao(jdbc);

    @Test
    void joinOnceUsesInsertIgnoreReliantOnUniqueKey() {
        when(jdbc.update(anyString(), anyLong(), anyLong(), anyLong(), anyString())).thenReturn(1);

        assertTrue(dao.joinOnce(1L, 400L, 13L, "2026-09-15 10:00:00"));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), anyLong(), anyLong(), anyLong(), anyString());
        String s = sql.getValue();
        assertTrue(s.contains("INSERT IGNORE"), "必须用 INSERT IGNORE 依赖唯一键防重：" + s);
        assertTrue(s.contains("seckill_orders"), s);
    }

    @Test
    void joinOnceReturnsFalseWhenUniqueKeyHits() {
        when(jdbc.update(anyString(), anyLong(), anyLong(), anyLong(), anyString())).thenReturn(0);

        assertFalse(dao.joinOnce(1L, 400L, 13L, "2026-09-15 10:00:00"));
    }

    @Test
    void releaseOnceDeletesByUserAndSeckill() {
        dao.releaseOnce(1L, 400L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), anyLong(), anyLong());
        String s = sql.getValue();
        assertTrue(s.contains("DELETE FROM seckill_orders"), s);
        assertTrue(s.contains("user_id = ?"), s);
        assertTrue(s.contains("seckill_id = ?"), s);
    }
}
