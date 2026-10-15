package com.example.takeout.dao;

import com.example.takeout.model.RefundRecord;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

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
        jdbc.update("INSERT INTO refund_records(order_id, user_id, merchant_id, reason_type, reason, amount, status, apply_time, process_time, reject_reason) VALUES(?,?,?,?,?,?,?,?,?,?)",
                orderId, userId, merchantId, reasonType, reason, amount, "PENDING", applyTime, "", "");
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
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
