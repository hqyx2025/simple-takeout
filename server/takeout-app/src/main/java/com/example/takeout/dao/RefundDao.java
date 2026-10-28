package com.example.takeout.dao;

import com.example.takeout.model.RefundRecord;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Repository;

import java.sql.Statement;
import java.util.List;
import java.util.Optional;

/**
 * 退款记录数据访问（演进项：用户申请退款 + 管理端审批）
 */
@Repository
public class RefundDao {

    private static final RowMapper<RefundRecord> MAPPER = (rs, i) -> new RefundRecord(
            rs.getLong("id"),
            rs.getLong("order_id"),
            rs.getLong("user_id"),
            rs.getLong("merchant_id"),
            rs.getString("reason_type"),
            rs.getString("reason"),
            rs.getBigDecimal("amount"),
            rs.getString("status"),
            rs.getString("apply_time"),
            rs.getString("process_time"),
            rs.getString("reject_reason"),
            images(rs.getString("evidence_images")), images(rs.getString("merchant_evidence_images")),
            rs.getString("merchant_response"), rs.getInt("appeal_count"), rs.getString("appeal_reason"),
            images(rs.getString("appeal_images")), rs.getInt("original_escrow"),
            rs.getInt("settled_before"), rs.getBigDecimal("merchant_amount"),
            rs.getBigDecimal("platform_amount"), rs.getString("refund_time")
    );

    private static final com.fasterxml.jackson.databind.ObjectMapper JSON = new com.fasterxml.jackson.databind.ObjectMapper();

    private static List<String> images(String value) throws java.sql.SQLException {
        if (value == null || value.isBlank()) return List.of();
        try {
            return JSON.readValue(value, new com.fasterxml.jackson.core.type.TypeReference<List<String>>() {});
        } catch (java.io.IOException error) {
            throw new java.sql.SQLException("售后证据数据损坏", error);
        }
    }

    private final JdbcTemplate jdbc;

    public RefundDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public long insert(long orderId, long userId, long merchantId, String reasonType, String reason, double amount, String applyTime) {
        return insert(orderId, userId, merchantId, reasonType, reason, amount, applyTime, null);
    }

    public long insert(long orderId, long userId, long merchantId, String reasonType, String reason,
                       double amount, String applyTime, String requestKey) {
        GeneratedKeyHolder keys = new GeneratedKeyHolder();
        jdbc.update(connection -> {
            var statement = connection.prepareStatement("INSERT INTO refund_records(order_id, user_id, merchant_id, " +
                    "reason_type, reason, amount, status, apply_time, process_time, reject_reason, request_key) " +
                    "VALUES(?,?,?,?,?,?,'PENDING',?,'','',?)", Statement.RETURN_GENERATED_KEYS);
            statement.setLong(1, orderId);
            statement.setLong(2, userId);
            statement.setLong(3, merchantId);
            statement.setString(4, reasonType);
            statement.setString(5, reason);
            statement.setDouble(6, amount);
            statement.setString(7, applyTime);
            statement.setString(8, requestKey);
            return statement;
        }, keys);
        Number key = keys.getKey();
        if (key == null) throw new IllegalStateException("退款申请主键未返回");
        return key.longValue();
    }

    public long insertAfterSales(long orderId, long userId, long merchantId, String reasonType,
                                 String reason, java.math.BigDecimal amount, String applyTime,
                                 String requestKey, String evidenceImages, int originalEscrow) {
        GeneratedKeyHolder keys = new GeneratedKeyHolder();
        jdbc.update(connection -> {
            var statement = connection.prepareStatement("INSERT INTO refund_records(order_id,user_id,merchant_id," +
                    "reason_type,reason,amount,status,apply_time,request_key,evidence_images,original_escrow,settled_before) " +
                    "VALUES(?,?,?,?,?,?,'PENDING',?,?,?,?,?)", Statement.RETURN_GENERATED_KEYS);
            statement.setLong(1, orderId);
            statement.setLong(2, userId);
            statement.setLong(3, merchantId);
            statement.setString(4, reasonType);
            statement.setString(5, reason);
            statement.setBigDecimal(6, amount);
            statement.setString(7, applyTime);
            statement.setString(8, requestKey);
            statement.setString(9, evidenceImages);
            statement.setInt(10, originalEscrow);
            statement.setInt(11, originalEscrow == 1 ? 1 : 0);
            return statement;
        }, keys);
        if (keys.getKey() == null) throw new IllegalStateException("退款申请主键未返回");
        return keys.getKey().longValue();
    }

    public java.math.BigDecimal refundedAmount(long orderId) {
        return jdbc.queryForObject("SELECT COALESCE(SUM(amount),0) FROM refund_records " +
                "WHERE order_id=? AND status='REFUNDED'", java.math.BigDecimal.class, orderId);
    }

    public java.math.BigDecimal merchantRefunded(long orderId) {
        return jdbc.queryForObject("SELECT COALESCE(SUM(merchant_amount),0) FROM refund_records " +
                "WHERE order_id=? AND status='REFUNDED'", java.math.BigDecimal.class, orderId);
    }

    public boolean complete(long id, java.math.BigDecimal merchant, java.math.BigDecimal platform, String now) {
        return jdbc.update("UPDATE refund_records SET status='REFUNDED',process_time=?,refund_time=?," +
                "merchant_amount=?,platform_amount=?,reject_reason='' WHERE id=? AND status='PENDING'",
                now, now, merchant, platform, id) == 1;
    }

    public boolean appeal(long id, String reason, String images, int escrow, String now) {
        return jdbc.update("UPDATE refund_records SET status='PENDING',appeal_count=1,appeal_reason=?," +
                "appeal_images=?,original_escrow=?,settled_before=?,apply_time=? " +
                "WHERE id=? AND status='REJECTED' AND appeal_count=0",
                reason, images, escrow, escrow == 1 ? 1 : 0, now, id) == 1;
    }

    public boolean merchantEvidence(long id, String response, String images) {
        return jdbc.update("UPDATE refund_records SET merchant_response=?,merchant_evidence_images=? " +
                "WHERE id=? AND status='PENDING'", response, images, id) == 1;
    }

    public Optional<RefundRecord> latestByOrder(long orderId) {
        return jdbc.query("SELECT * FROM refund_records WHERE order_id = ? ORDER BY id DESC LIMIT 1", MAPPER, orderId).stream().findFirst();
    }

    public List<RefundRecord> listByOrder(long orderId) {
        return jdbc.query("SELECT * FROM refund_records WHERE order_id = ? ORDER BY id DESC", MAPPER, orderId);
    }

    public Optional<RefundRecord> findByRequestKey(long orderId, String requestKey) {
        Optional<RefundRecord> mapped = jdbc.query("SELECT r.* FROM refund_apply_requests q " +
                        "JOIN refund_records r ON r.id = q.refund_id AND r.order_id = q.order_id " +
                        "WHERE q.order_id = ? AND q.request_key = ?", MAPPER, orderId, requestKey).stream().findFirst();
        if (mapped.isPresent()) return mapped;
        // 兼容映射表上线前已写入的申请；已有主请求 key 的重放仍然有效。
        return jdbc.query("SELECT * FROM refund_records WHERE order_id = ? AND request_key = ?",
                MAPPER, orderId, requestKey).stream().findFirst();
    }

    /** 持有订单行锁时调用，与新申请或复用 PENDING 的响应同事务持久化；绝不重定向已有 key。 */
    public void bindApplyRequest(long orderId, String requestKey, long refundId) {
        jdbc.update("INSERT INTO refund_apply_requests(order_id, request_key, refund_id) VALUES(?,?,?)",
                orderId, requestKey, refundId);
    }

    public Optional<RefundRecord> findPending(long orderId) {
        return jdbc.query("SELECT * FROM refund_records WHERE order_id = ? AND status = 'PENDING' " +
                "ORDER BY id DESC LIMIT 1", MAPPER, orderId).stream().findFirst();
    }

    public Optional<RefundRecord> findById(long id) {
        return jdbc.query("SELECT * FROM refund_records WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public Optional<RefundRecord> findByIdForUpdate(long id) {
        return jdbc.query("SELECT * FROM refund_records WHERE id = ? FOR UPDATE", MAPPER, id).stream().findFirst();
    }

    public List<RefundRecord> listAll() {
        return jdbc.query("SELECT * FROM refund_records ORDER BY id DESC", MAPPER);
    }

    public List<RefundRecord> listByStatus(String status) {
        return jdbc.query("SELECT * FROM refund_records WHERE status = ? ORDER BY id DESC", MAPPER, status);
    }

    public int countForAdmin(String status) {
        String sql = status == null || status.isBlank()
                ? "SELECT COUNT(*) FROM refund_records" : "SELECT COUNT(*) FROM refund_records WHERE status = ?";
        Integer count = status == null || status.isBlank()
                ? jdbc.queryForObject(sql, Integer.class)
                : jdbc.queryForObject(sql, Integer.class, status);
        return count == null ? 0 : count;
    }

    public List<RefundRecord> listForAdmin(String status, int pageSize, long offset) {
        if (status == null || status.isBlank()) {
            return jdbc.query("SELECT * FROM refund_records ORDER BY id DESC LIMIT ? OFFSET ?",
                    MAPPER, pageSize, offset);
        }
        return jdbc.query("SELECT * FROM refund_records WHERE status = ? ORDER BY id DESC LIMIT ? OFFSET ?",
                MAPPER, status, pageSize, offset);
    }

    /** 同一订单存在进行中的退款申请时返回 true（防止重复申请）。 */
    public boolean existsPending(long orderId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM refund_records WHERE order_id = ? AND status = 'PENDING'",
                Integer.class, orderId);
        return count != null && count > 0;
    }

    public boolean updateStatus(long id, String status, String processTime, String rejectReason) {
        return jdbc.update("UPDATE refund_records SET status = ?, process_time = ?, reject_reason = ? " +
                        "WHERE id = ? AND status = 'PENDING'",
                status, processTime, rejectReason, id) == 1;
    }
}
