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
            rs.getDouble("amount"),
            rs.getString("status"),
            rs.getString("apply_time"),
            rs.getString("process_time"),
            rs.getString("reject_reason")
    );

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
