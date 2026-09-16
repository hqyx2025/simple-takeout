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
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 逻辑删除 SQL 契约：内容类表（goods/categories/banners/announcements）删除改打标
 * deleted=1、查询过滤 deleted=0，不做物理 DELETE。缺陷形态：硬删除会把商品/分类/Banner/公告
 * 的既有引用（订单 JSON 快照之外的历史、统计、审计）一并抹掉，逻辑删除保留数据可追溯。
 */
class SoftDeleteSqlTest {

    @Test
    void goodsDeleteSetsDeletedFlag() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        GoodsDao dao = new GoodsDao(jdbc, mock(GoodsSpecDao.class));

        dao.delete(7);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), eq(7L));
        assertEquals("UPDATE goods SET deleted = 1 WHERE id = ?", sql.getValue());
    }

    @Test
    void goodsReadQueriesFilterDeleted() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        GoodsDao dao = new GoodsDao(jdbc, mock(GoodsSpecDao.class));
        when(jdbc.query(anyString(), any(RowMapper.class), any(Object[].class))).thenReturn(List.of());

        dao.listByStore(10);
        dao.findById(5);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc, times(2)).query(sql.capture(), any(RowMapper.class), any(Object[].class));
        assertTrue(sql.getAllValues().get(0).contains("deleted = 0"), sql.getAllValues().get(0));
        assertTrue(sql.getAllValues().get(1).contains("deleted = 0"), sql.getAllValues().get(1));
    }

    @Test
    void bannerAndAnnouncementListFilterDeleted() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(), any(RowMapper.class))).thenReturn(List.of());

        new BannerDao(jdbc).listActive();
        new AnnouncementDao(jdbc).listActive();

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc, times(2)).query(sql.capture(), any(RowMapper.class));
        assertEquals(2, sql.getAllValues().size());
        assertTrue(sql.getAllValues().get(0).contains("deleted = 0"));
        assertTrue(sql.getAllValues().get(1).contains("deleted = 0"));
    }
}
