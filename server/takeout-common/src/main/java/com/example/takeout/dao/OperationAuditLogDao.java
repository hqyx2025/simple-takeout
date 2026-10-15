package com.example.takeout.dao;

import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public class OperationAuditLogDao {

    private final JdbcTemplate jdbc;

    public OperationAuditLogDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void insert(long operatorId, int operatorRole, long orderId, int statusAfter, String action,
                       String method, String path, String outcome, int status, String traceId, long createdAt) {
        jdbc.update("INSERT INTO operation_audit_logs(operator_id, operator_role, order_id, status_after, action, " +
                        "http_method, request_path, outcome, http_status, trace_id, created_at) " +
                        "VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                operatorId, operatorRole, orderId, statusAfter, action, method, path,
                outcome, status, traceId, createdAt);
    }

    public int currentOrderStatus(long orderId) {
        try {
            Integer status = jdbc.queryForObject("SELECT status FROM orders WHERE id = ?", Integer.class, orderId);
            return status == null ? -1 : status;
        } catch (EmptyResultDataAccessException ignored) {
            return -1;
        }
    }

    public int count() {
        Integer total = jdbc.queryForObject("SELECT COUNT(*) FROM operation_audit_logs", Integer.class);
        return total == null ? 0 : total;
    }

    public List<OperationLog> list(int pageSize, long offset) {
        return jdbc.query("SELECT id, operator_id, operator_role, order_id, status_after, action, http_method, " +
                        "request_path, outcome, http_status, trace_id, created_at FROM operation_audit_logs " +
                        "ORDER BY id DESC LIMIT ? OFFSET ?",
                (rs, row) -> new OperationLog(rs.getLong("id"), rs.getLong("operator_id"),
                        rs.getInt("operator_role"), rs.getLong("order_id"), rs.getInt("status_after"),
                        rs.getString("action"), rs.getString("http_method"), rs.getString("request_path"),
                        rs.getString("outcome"), rs.getInt("http_status"), rs.getString("trace_id"),
                        rs.getLong("created_at")), pageSize, offset);
    }

    public record OperationLog(long id, long operatorId, int operatorRole, long orderId, int statusAfter,
                               String action, String method, String path, String outcome, int status,
                               String traceId, long createdAt) {
    }
}
