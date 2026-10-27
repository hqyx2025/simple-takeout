package com.example.takeout.dao;

import com.example.takeout.model.PaymentTransaction;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

@Repository
public class PaymentTransactionDao {

    private static final RowMapper<PaymentTransaction> MAPPER = (rs, i) -> new PaymentTransaction(
            rs.getLong("id"), rs.getLong("order_id"), rs.getLong("user_id"), rs.getString("channel"),
            rs.getBigDecimal("amount"), rs.getString("out_trade_no"), rs.getString("provider_transaction_id"),
            rs.getString("status"), rs.getString("payment_url"), rs.getString("create_time"),
            rs.getString("notify_time"), rs.getString("payment_mode"));

    private final JdbcTemplate jdbc;

    public PaymentTransactionDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public long insertPending(long orderId, long userId, String channel, BigDecimal amount,
                              String outTradeNo, String createTime) {
        return insertPending(orderId, userId, channel, amount, outTradeNo, createTime, "QR");
    }

    public long insertPending(long orderId, long userId, String channel, BigDecimal amount,
                              String outTradeNo, String createTime, String paymentMode) {
        jdbc.update("INSERT INTO payment_transactions(order_id,user_id,channel,amount,out_trade_no,status,active_order_id,create_time,payment_mode) " +
                        "VALUES(?,?,?,?,?,'PENDING',?,?,?)",
                orderId, userId, channel, amount, outTradeNo, orderId, createTime, paymentMode);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public Optional<PaymentTransaction> findActiveByOrder(long orderId) {
        return queryOne("SELECT * FROM payment_transactions WHERE active_order_id = ? AND status = 'PENDING' FOR UPDATE", orderId);
    }

    public Optional<PaymentTransaction> findLatestByOrder(long orderId) {
        return queryOne("SELECT * FROM payment_transactions WHERE order_id = ? ORDER BY id DESC LIMIT 1", orderId);
    }

    public Optional<PaymentTransaction> findByOutTradeNo(String outTradeNo) {
        return queryOne("SELECT * FROM payment_transactions WHERE out_trade_no = ?", outTradeNo);
    }

    public Optional<PaymentTransaction> findByOutTradeNoForUpdate(String outTradeNo) {
        return queryOne("SELECT * FROM payment_transactions WHERE out_trade_no = ? FOR UPDATE", outTradeNo);
    }

    public Optional<PaymentTransaction> findSuccessfulByOrder(long orderId) {
        return queryOne("SELECT * FROM payment_transactions WHERE order_id = ? AND status IN ('SUCCESS','REFUNDED') " +
                "ORDER BY id DESC LIMIT 1 FOR UPDATE", orderId);
    }

    public boolean setPaymentUrl(long id, String paymentUrl) {
        return jdbc.update("UPDATE payment_transactions SET payment_url = ? WHERE id = ? AND status = 'PENDING'",
                paymentUrl, id) == 1;
    }

    public void markFailed(long id) {
        jdbc.update("UPDATE payment_transactions SET status = 'FAILED', active_order_id = NULL " +
                "WHERE id = ? AND status = 'PENDING'", id);
    }

    public void markClosed(long id) {
        jdbc.update("UPDATE payment_transactions SET status = 'CLOSED', active_order_id = NULL " +
                "WHERE id = ? AND status = 'PENDING'", id);
    }

    public void markRefunded(long id) {
        jdbc.update("UPDATE payment_transactions SET status = 'REFUNDED' WHERE id = ? AND status = 'SUCCESS'", id);
    }

    public void markLateRefunded(long id, String providerTransactionId, String notifyTime) {
        jdbc.update("UPDATE payment_transactions SET status = 'LATE_REFUNDED', provider_transaction_id = ?, " +
                        "notify_time = ?, active_order_id = NULL WHERE id = ? AND status IN ('PENDING','CLOSED')",
                providerTransactionId, notifyTime, id);
    }

    public boolean markSuccess(long id, String providerTransactionId, String notifyTime) {
        return jdbc.update("UPDATE payment_transactions SET status = 'SUCCESS', provider_transaction_id = ?, " +
                        "notify_time = ?, active_order_id = NULL WHERE id = ? AND status = 'PENDING'",
                providerTransactionId, notifyTime, id) == 1;
    }

    private Optional<PaymentTransaction> queryOne(String sql, Object... args) {
        List<PaymentTransaction> rows = jdbc.query(sql, MAPPER, args);
        return rows.stream().findFirst();
    }
}
