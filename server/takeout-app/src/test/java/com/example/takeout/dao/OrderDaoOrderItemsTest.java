package com.example.takeout.dao;

import com.example.takeout.model.Order;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OrderDaoOrderItemsTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final OrderDao dao = new OrderDao(jdbc);

    @Test
    void insertsEachOrderLineWithItsSpecificationAndPromotionSnapshot() {
        dao.insertItems(41, List.of(
                new Order.OrderItem(7, "牛肉粉", 18.5, 2, "/food.png", 71, "大份", 5),
                new Order.OrderItem(8, "酸梅汤", 0, 1, "", 0, "", 0)));

        String sql = "INSERT INTO order_items(order_id, line_no, goods_id, goods_name, unit_price, quantity, " +
                "image, spec_id, spec_name, seckill_id) VALUES(?,?,?,?,?,?,?,?,?,?)";
        verify(jdbc).update(sql, 41L, 1, 7L, "牛肉粉", 18.5, 2, "/food.png", 71L, "大份", 5L);
        verify(jdbc).update(sql, 41L, 2, 8L, "酸梅汤", 0.0, 1, "", 0L, "", 0L);
    }

    @Test
    void emptyOrderLinesDoNotIssueSql() {
        dao.insertItems(41, List.of());

        verify(jdbc, never()).update(org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.any(Object[].class));
    }

    @Test
    void insertsLegacyAndDatetimeOrderTimesTogether() {
        when(jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class)).thenReturn(51L);
        Order order = new Order(0, "NO51", 7, 10, "Store", 0, "[]", "{}", 18, 2,
                0, 20, "", 0, 0, "2026-10-14 09:00:00", "", "", "", "", "", 0, "DELIVERY");

        assertEquals(51L, dao.insert(order));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).update(sql.capture(), args.capture());
        assertTrue(sql.getValue().contains("create_time_dt, pay_time_dt, accept_time_dt"));
        assertEquals(28, args.getValue().length);
    }
}
