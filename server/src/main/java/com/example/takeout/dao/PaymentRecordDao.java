package com.example.takeout.dao;

import com.example.takeout.model.PaymentRecord;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;

/** 支付/退款明细台账。 */
@Repository
public class PaymentRecordDao {

    private static final RowMapper<PaymentRecord> MAPPER = (rs, i) -> new PaymentRecord(
            rs.getLong("id"),
            rs.getLong("order_id"),
            rs.getLong("user_id"),
            rs.getDouble("amount"),
            rs.getString("type"),
            rs.getString("channel"),
            rs.getString("status"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public PaymentRecordDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public long insert(long orderId, long userId, double amount, String type, String channel,
                       String status, String createTime) {
        jdbc.update("INSERT INTO payment_records(order_id, user_id, amount, type, channel, status, create_time) VALUES(?,?,?,?,?,?,?)",
                orderId, userId, amount, type, channel, status, createTime);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public List<PaymentRecord> listByUser(long userId, int limit) {
        return jdbc.query("SELECT * FROM payment_records WHERE user_id = ? ORDER BY id DESC LIMIT ?",
                MAPPER, userId, Math.max(1, Math.min(limit, 100)));
    }
}
