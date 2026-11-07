package com.example.takeout.dao;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.concurrent.Callable;

/** Durable per-group receipt; a row lock serializes concurrent redeliveries. */
@Repository
public class DomainEventInbox {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transactions;

    public DomainEventInbox(JdbcTemplate jdbc, TransactionTemplate transactions) {
        this.jdbc = jdbc;
        this.transactions = transactions;
    }

    public void runOnce(String group, long eventId, Runnable action) {
        transactions.executeWithoutResult(status -> {
            boolean completed = completedReceipt(group, eventId);
            // Verify failure storage before external effects. A failed attempt rolls this deletion back.
            resolveFailure(group, failureKey(eventId, ""));
            if (!completed) {
                // External push remains at least once if the process dies after sending but before commit.
                action.run();
                jdbc.update("UPDATE mq_consumptions SET consumed_at=CURRENT_TIMESTAMP "
                        + "WHERE consumer_group=? AND event_id=?", group, eventId);
            }
        });
    }

    private boolean completedReceipt(String group, long eventId) {
        jdbc.update("INSERT INTO mq_consumptions(consumer_group,event_id) VALUES(?,?) "
                + "ON DUPLICATE KEY UPDATE event_id=event_id", group, eventId);
        return Boolean.TRUE.equals(jdbc.queryForObject("SELECT consumed_at IS NOT NULL FROM mq_consumptions "
                + "WHERE consumer_group=? AND event_id=? FOR UPDATE", Boolean.class, group, eventId));
    }

    /** Called after the failed processing transaction rolls back. A completed competing attempt wins. */
    public void recordFailure(String group, String key, long eventId) {
        transactions.executeWithoutResult(status -> {
            if (eventId > 0 && completedReceipt(group, eventId)) return;
            jdbc.update("INSERT INTO mq_consumer_failures(consumer_group,event_key) VALUES(?,?) "
                    + "ON DUPLICATE KEY UPDATE last_failed_at=CURRENT_TIMESTAMP(6),attempts=attempts+1", group, key);
        });
    }

    public void resolveFailure(String group, String key) {
        jdbc.update("DELETE FROM mq_consumer_failures WHERE consumer_group=? AND event_key=?", group, key);
    }

    public record FailureStats(long count, long oldestSeconds) { }

    public FailureStats failures(String group) {
        return jdbc.queryForObject("SELECT COUNT(*) failed, "
                        + "GREATEST(COALESCE(TIMESTAMPDIFF(SECOND,MIN(first_failed_at),CURRENT_TIMESTAMP(6)),0),0) age "
                        + "FROM mq_consumer_failures WHERE consumer_group=?",
                (row, index) -> new FailureStats(row.getLong("failed"), row.getLong("age")), group);
    }

    /** No lease expiry or fail-open: the DB lock covers reading, publishing and committing the broker cursor. */
    public int serializeReplay(String group, Callable<Integer> action) {
        Integer result = transactions.execute(status -> {
            // The duplicate-key update acquires the same exclusive row lock in every app replica.
            jdbc.update("INSERT INTO mq_replay_locks(consumer_group) VALUES(?) "
                    + "ON DUPLICATE KEY UPDATE consumer_group=consumer_group", group);
            try { return action.call(); }
            catch (RuntimeException e) { throw e; }
            catch (Exception e) { throw new IllegalStateException("Dead-letter replay failed; confirmed cursor progress is retained", e); }
        });
        return result == null ? 0 : result;
    }

    public static String failureKey(long eventId, String messageId) {
        if (eventId > 0) return "event-" + eventId;
        try {
            return "message-" + HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(messageId.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
}
