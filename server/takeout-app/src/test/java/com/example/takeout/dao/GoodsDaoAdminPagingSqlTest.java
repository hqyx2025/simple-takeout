package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 管理端商品分页的 SQL 契约：listForAdmin 必须追加 LIMIT/OFFSET，且与 countForAdmin 共用同一套筛选。
 * 缺陷形态：goods 是仓库里唯一接近千行的表，全量进内存会在数据涨上去后变成 OOM；分页若只在某处漏加 LIMIT
 * 就白做了。这里钉住翻页 SQL 与总数 SQL 都带 keyword/status 筛选。
 */
class GoodsDaoAdminPagingSqlTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final GoodsDao dao = new GoodsDao(jdbc, mock(GoodsSpecDao.class));

    @Test
    void listForAdminAppendsLimitAndOffsetWhenPaging() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listForAdmin("面", 1, 50, 100);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), args.capture());
        assertTrue(sql.getValue().endsWith("ORDER BY g.id DESC LIMIT ? OFFSET ?"), "翻页 SQL 缺 LIMIT/OFFSET：" + sql.getValue());
        // 参数顺序：keyword 两次（商品名/店铺名）→ status → limit → offset
        Object[] a = args.getValue();
        assertEquals("%面%", a[0]);
        assertEquals("%面%", a[1]);
        assertEquals(1, a[2]);
        assertEquals(50, a[3]);
        assertEquals(100, a[4]);
    }

    @Test
    void legacyNoPagingStillWorks() {
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listForAdmin(null, null);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(), any(RowMapper.class), any(Object[].class));
        assertTrue(sql.getValue().endsWith("ORDER BY g.id DESC"), "无分页调用不应带 LIMIT：" + sql.getValue());
    }

    @Test
    void countForAdminSharesSameFilter() {
        when(jdbc.queryForObject(anyString(), eq(Integer.class), any(Object[].class))).thenReturn(959);

        int total = dao.countForAdmin("面", 1);

        assertEquals(959, total);
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).queryForObject(sql.capture(), eq(Integer.class), args.capture());
        String s = sql.getValue();
        assertTrue(s.contains("COUNT(*)"), "总数 SQL 应为聚合查询：" + s);
        assertTrue(s.contains("(g.name LIKE ? OR s.name LIKE ?)"), "总数遗漏商品名/店铺名筛选：" + s);
        assertTrue(s.contains("AND g.status = ?"), "总数遗漏状态筛选：" + s);
        Object[] a = args.getValue();
        assertEquals("%面%", a[0]);
        assertEquals("%面%", a[1]);
        assertEquals(1, a[2]);
    }
}