package com.example.takeout.config;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.startsWith;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DataSeederStockTest {
    @Test
    void existingZeroStockIsNeverRestockedDuringSchemaInitialization() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), eq(Integer.class), eq("goods"), anyString())).thenReturn(1);
        when(jdbc.queryForObject("SELECT COUNT(*) FROM goods WHERE stock = 0", Integer.class)).thenReturn(1);
        var initializeGoods = DataSeeder.class.getDeclaredMethod("ensureGoodsColumns");
        initializeGoods.setAccessible(true);

        initializeGoods.invoke(new DataSeeder(jdbc));

        verify(jdbc, never()).update(startsWith("UPDATE goods SET stock"));
        verify(jdbc, never()).execute(startsWith("ALTER TABLE goods ADD COLUMN stock"));
    }
}
