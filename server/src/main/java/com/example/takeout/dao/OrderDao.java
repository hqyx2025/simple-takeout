package com.example.takeout.dao;

import com.example.takeout.model.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * 订单数据访问
 */
@Repository
public class OrderDao {

    private static final RowMapper<Order> MAPPER = (rs, i) -> new Order(
            rs.getLong("id"),
            rs.getString("order_no"),
            rs.getLong("user_id"),
            rs.getLong("store_id"),
            rs.getString("store_name"),
            rs.getInt("status"),
            rs.getString("items"),
            rs.getString("address"),
            rs.getDouble("goods_amount"),
            rs.getDouble("delivery_fee"),
            rs.getDouble("discount"),
            rs.getDouble("pay_amount"),
            rs.getString("remark"),
            rs.getInt("reviewed"),
            rs.getString("create_time"),
            rs.getString("pay_time"),
            rs.getString("accept_time"),
            rs.getString("deliver_time"),
            rs.getString("complete_time")
    );

    private final JdbcTemplate jdbc;

    public OrderDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public long insert(Order o) {
        jdbc.update("INSERT INTO orders(order_no, user_id, store_id, store_name, status, items, address, goods_amount, delivery_fee, discount, pay_amount, remark, reviewed, create_time, pay_time, accept_time, deliver_time, complete_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                o.orderNo(), o.userId(), o.storeId(), o.storeName(), o.status(), o.items(), o.address(),
                o.goodsAmount(), o.deliveryFee(), o.discount(), o.payAmount(), o.remark(), o.reviewed(),
                o.createTime(), o.payTime(), o.acceptTime(), o.deliverTime(), o.completeTime());
        return jdbc.queryForObject("SELECT last_insert_rowid()", Long.class);
    }

    public List<Order> listByUser(long userId) {
        return jdbc.query("SELECT * FROM orders WHERE user_id = ? ORDER BY id DESC", MAPPER, userId);
    }

    public List<Order> listByStore(long storeId) {
        return jdbc.query("SELECT * FROM orders WHERE store_id = ? ORDER BY id DESC", MAPPER, storeId);
    }

    public Optional<Order> findById(long id) {
        return jdbc.query("SELECT * FROM orders WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public void updateStatus(long id, int status, String timeField, String timeValue) {
        jdbc.update("UPDATE orders SET status = ?, " + timeField + " = ? WHERE id = ?", status, timeValue, id);
    }

    public void markReviewed(long id) {
        jdbc.update("UPDATE orders SET reviewed = 1 WHERE id = ?", id);
    }
}
