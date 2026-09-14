package com.example.takeout.dao;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * 事务性 Outbox 数据访问。
 *
 * 事件与业务数据在同一事务写入，保证「业务成功则事件必达、业务回滚则事件不存在」；
 * 中继任务扫描 status=0 的记录投递到 Redis Stream，成功后置为 1。
 */
@Repository
public class OutboxEventDao {

    /** 待投递 */
    public static final int STATUS_PENDING = 0;

    /** 已投递 */
    public static final int STATUS_SENT = 1;

    public record OutboxEvent(long id, String eventType, long orderId, String payload,
                              int status, int retryCount, String createTime) {
    }

    private static final RowMapper<OutboxEvent> MAPPER = (rs, i) -> new OutboxEvent(
            rs.getLong("id"),
            rs.getString("event_type"),
            rs.getLong("order_id"),
            rs.getString("payload"),
            rs.getInt("status"),
            rs.getInt("retry_count"),
            rs.getString("create_time"));

    private final JdbcTemplate jdbc;

    public OutboxEventDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public long insert(String eventType, long orderId, String payload, String now) {
        jdbc.update("INSERT INTO outbox_events(event_type, order_id, payload, status, retry_count, create_time) " +
                "VALUES(?,?,?,0,0,?)", eventType, orderId, payload, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    /** 取一批待投递事件（按 id 顺序保证同一订单的事件相对有序）。 */
    public List<OutboxEvent> listPending(int limit) {
        return jdbc.query("SELECT * FROM outbox_events WHERE status = 0 ORDER BY id LIMIT ?", MAPPER, limit);
    }

    public Optional<OutboxEvent> findById(long id) {
        return jdbc.query("SELECT * FROM outbox_events WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    /** 标记投递成功。 */
    public void markSent(long id) {
        jdbc.update("UPDATE outbox_events SET status = 1 WHERE id = ?", id);
    }

    /** 记录一次失败（超过上限后不再重试，避免死信无限占用扫描配额）。 */
    public void markRetry(long id) {
        jdbc.update("UPDATE outbox_events SET retry_count = retry_count + 1 WHERE id = ?", id);
    }

    /** 超过重试上限的待投递事件（用于日志告警）。 */
    public int countExhausted(int maxRetry) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM outbox_events WHERE status = 0 AND retry_count >= ?", Integer.class, maxRetry);
        return count == null ? 0 : count;
    }

    public int countPending() {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM outbox_events WHERE status = 0", Integer.class);
        return count == null ? 0 : count;
    }

    /** 清理已投递的历史事件，避免表无限增长。 */
    public int deleteSentBefore(String time) {
        return jdbc.update("DELETE FROM outbox_events WHERE status = 1 AND create_time < ?", time);
    }
}
