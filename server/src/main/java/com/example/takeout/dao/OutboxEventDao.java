package com.example.takeout.dao;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * 事务性 Outbox 数据访问。
 *
 * 事件与业务数据在同一事务写入，保证「业务成功则事件必达、业务回滚则事件不存在」；
 * 中继任务扫描 status=0 的记录投递到 Redis Stream，成功后置为 1。
 *
 * <p><b>多实例行级认领</b>：原实现在多实例下会让两个中继同时捞到同一批事件（重复搬运）。
 * 现改为 {@code SELECT ... FOR UPDATE SKIP LOCKED} 在事务内一次性「选出并盖认领戳」：
 * 被实例 A 锁住的行会被实例 B 直接跳过（而不是排队等待），因此吞吐随实例数线性增长。</p>
 */
@Repository
public class OutboxEventDao {

    /** 待投递 */
    public static final int STATUS_PENDING = 0;

    /** 已投递 */
    public static final int STATUS_SENT = 1;

    /** 未认领的租约值：0 保证存量行（老库补列后）立刻可被认领。 */
    public static final long NO_LEASE = 0L;

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
    private final TransactionTemplate tx;

    public OutboxEventDao(JdbcTemplate jdbc, TransactionTemplate tx) {
        this.jdbc = jdbc;
        this.tx = tx;
    }

    public long insert(String eventType, long orderId, String payload, String now) {
        jdbc.update("INSERT INTO outbox_events(event_type, order_id, payload, status, retry_count, create_time) " +
                "VALUES(?,?,?,0,0,?)", eventType, orderId, payload, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    /**
     * 取一批待投递事件（按 id 顺序保证同一订单的事件相对有序）。
     *
     * <p>单实例/测试用的只读扫描。多实例中继请改用
     * {@link #claimPending(int, String, long, long)}，否则会重复搬运。</p>
     */
    public List<OutboxEvent> listPending(int limit) {
        return jdbc.query("SELECT * FROM outbox_events WHERE status = 0 ORDER BY id LIMIT ?", MAPPER, limit);
    }

    /**
     * 行级认领一批待投递事件（多实例安全）。
     *
     * <p>在一个事务内先 {@code FOR UPDATE SKIP LOCKED} 选出可认领的行，再一次性盖上
     * {@code owner} 与 {@code lease_until}。其他实例会跳过这些行，因此同一事件只会被一个实例搬运。</p>
     *
     * <p><b>租约语义</b>：认领后若实例崩溃（未 markSent / markRetry），该行不会永远滞留——
     * 租约到期（{@code leaseUntil} 已过）后任何实例都能重新认领。因此租约时长要显著大于
     * 一次投递的耗时，又不能长到让崩溃事件长时间无人处理。</p>
     *
     * @param limit     本批最多认领条数
     * @param owner     认领者标识（实例 ID），仅用于诊断「谁搬走了这条事件」
     * @param now       当前时间（epoch 毫秒），用于判断哪些行租约已过期
     * @param leaseUntil 本次认领的租约到期时间（epoch 毫秒）
     * @return 本次认领到的事件；已被其他实例认领的行不会出现在结果里
     */
    public List<OutboxEvent> claimPending(int limit, String owner, long now, long leaseUntil) {
        List<OutboxEvent> claimed = tx.execute(status -> {
            List<OutboxEvent> candidates = jdbc.query(
                    "SELECT * FROM outbox_events WHERE status = 0 AND lease_until < ? " +
                            "ORDER BY id LIMIT ? FOR UPDATE SKIP LOCKED",
                    MAPPER, now, limit);
            if (candidates.isEmpty()) {
                return candidates;
            }
            List<Object[]> batchArgs = new ArrayList<>(candidates.size());
            for (OutboxEvent event : candidates) {
                batchArgs.add(new Object[]{owner, leaseUntil, event.id()});
            }
            jdbc.batchUpdate("UPDATE outbox_events SET owner = ?, lease_until = ? WHERE id = ?", batchArgs);
            return candidates;
        });
        return claimed == null ? List.of() : claimed;
    }

    public Optional<OutboxEvent> findById(long id) {
        return jdbc.query("SELECT * FROM outbox_events WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    /** 标记投递成功。 */
    public void markSent(long id) {
        jdbc.update("UPDATE outbox_events SET status = 1, lease_until = 0 WHERE id = ?", id);
    }

    /**
     * 记录一次失败。
     *
     * <p>必须同时释放租约：否则投递失败的事件要干等到租约到期，其他健康实例也帮不上忙。
     * 事件已持久化在数据库，重试几乎零成本，故这里【永不放弃】投递，retry_count 只用于告警。</p>
     */
    public void markRetry(long id) {
        jdbc.update("UPDATE outbox_events SET retry_count = retry_count + 1, lease_until = 0 WHERE id = ?", id);
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