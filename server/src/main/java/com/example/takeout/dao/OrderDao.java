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
            rs.getInt("escrow_status"),
            rs.getString("create_time"),
            rs.getString("pay_time"),
            rs.getString("accept_time"),
            rs.getString("deliver_time"),
            rs.getString("complete_time"),
            rs.getString("expect_time")
    );

    private final JdbcTemplate jdbc;

    public OrderDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public long insert(Order o) {
        jdbc.update("INSERT INTO orders(order_no, user_id, store_id, store_name, status, items, address, goods_amount, delivery_fee, discount, pay_amount, remark, reviewed, escrow_status, create_time, pay_time, accept_time, deliver_time, complete_time, expect_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                o.orderNo(), o.userId(), o.storeId(), o.storeName(), o.status(), o.items(), o.address(),
                o.goodsAmount(), o.deliveryFee(), o.discount(), o.payAmount(), o.remark(), o.reviewed(),
                0, o.createTime(), o.payTime(), o.acceptTime(), o.deliverTime(), o.completeTime(), o.expectTime());
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public List<Order> listByUser(long userId) {
        return jdbc.query("SELECT * FROM orders WHERE user_id = ? ORDER BY id DESC", MAPPER, userId);
    }

    public List<Order> listByStore(long storeId) {
        return jdbc.query("SELECT * FROM orders WHERE store_id = ? ORDER BY id DESC", MAPPER, storeId);
    }

    public List<Order> listAll() {
        return jdbc.query("SELECT * FROM orders ORDER BY id DESC", MAPPER);
    }

    public Optional<Order> findById(long id) {
        return jdbc.query("SELECT * FROM orders WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public void updateStatus(long id, int status, String timeField, String timeValue) {
        jdbc.update("UPDATE orders SET status = ?, " + timeField + " = ? WHERE id = ?", status, timeValue, id);
    }

    /** 仅更新订单状态，不写时间字段（退款申请/审批回退使用）。 */
    public void updateStatusOnly(long id, int status) {
        jdbc.update("UPDATE orders SET status = ? WHERE id = ?", status, id);
    }

    public void markReviewed(long id) {
        jdbc.update("UPDATE orders SET reviewed = 1 WHERE id = ?", id);
    }

    /** 将托管款标记为已退款，条件更新避免重复退款。 */
    public boolean refundEscrow(long id) {
        return jdbc.update("UPDATE orders SET escrow_status = 2 WHERE id = ? AND escrow_status = 0", id) == 1;
    }

    /** 将托管款标记为已结算，条件更新避免重复给商户打款。 */
    public boolean releaseEscrow(long id) {
        return jdbc.update("UPDATE orders SET escrow_status = 1 WHERE id = ? AND escrow_status = 0", id) == 1;
    }

    public List<Order> listSettledByStore(long storeId) {
        return jdbc.query("SELECT * FROM orders WHERE store_id = ? AND status = 4 AND escrow_status = 1 ORDER BY id DESC",
                MAPPER, storeId);
    }

    // ============ 四端改造：骑手配送 ============

    /** 商户出餐完成：写 ready_time，订单进入待取餐池（幂等，重复调用不覆盖）。 */
    public boolean markReady(long id, String now) {
        return jdbc.update("UPDATE orders SET ready_time = ? WHERE id = ? AND status = 2 AND ready_time = ''",
                now, id) == 1;
    }

    /** 待取餐池：已出餐但尚未分配骑手。 */
    public List<Order> listRiderPool() {
        return jdbc.query("SELECT * FROM orders WHERE status = 2 AND ready_time <> '' AND rider_id = 0 ORDER BY ready_time",
                MAPPER);
    }

    /** 骑手抢单：条件更新，防并发重复抢单（失败=已被他人抢走）。 */
    public boolean tryAssignRider(long id, long riderId) {
        return jdbc.update("UPDATE orders SET rider_id = ? WHERE id = ? AND rider_id = 0 AND status = 2 AND ready_time <> ''",
                riderId, id) == 1;
    }

    /** 骑手取餐：2 → 3（仅本人接的订单）。 */
    public boolean riderPickup(long id, long riderId, String now) {
        return jdbc.update("UPDATE orders SET status = 3, deliver_time = ? WHERE id = ? AND rider_id = ? AND status = 2",
                now, id, riderId) == 1;
    }

    /** 骑手送达：3 → 4（仅本人接的订单）。 */
    public boolean riderDeliver(long id, long riderId, String now) {
        return jdbc.update("UPDATE orders SET status = 4, complete_time = ? WHERE id = ? AND rider_id = ? AND status = 3",
                now, id, riderId) == 1;
    }

    public List<Order> listByRider(long riderId) {
        return jdbc.query("SELECT * FROM orders WHERE rider_id = ? ORDER BY id DESC", MAPPER, riderId);
    }

    public long findRiderId(long orderId) {
        Long riderId = jdbc.queryForObject("SELECT rider_id FROM orders WHERE id = ?", Long.class, orderId);
        return riderId == null ? 0 : riderId;
    }
}
