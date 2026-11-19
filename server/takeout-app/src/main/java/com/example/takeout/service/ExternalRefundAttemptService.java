package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.model.PaymentTransaction;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

/** Intent commits before channel I/O; final bookkeeping and DONE share the business transaction. */
@Service
public class ExternalRefundAttemptService {
    public record Cancellation(String source, String reasonCode, String reason, long operatorId,
                               String note, long goodsId, long specId) {}
    public record Attempt(String refundNo, String kind, long orderId, long paymentId, long refundId,
                          String channel, String outTradeNo, String providerTransactionId,
                          BigDecimal amount, BigDecimal originalAmount, String metadataJson, String status) {}
    private final JdbcTemplate db;
    private final TransactionTemplate transactions;
    private final ObjectMapper json;

    public ExternalRefundAttemptService(JdbcTemplate db, PlatformTransactionManager manager, ObjectMapper json) {
        this.db = db; this.json = json;
        transactions = new TransactionTemplate(manager);
    }

    public Attempt prepare(String kind, PaymentTransaction payment, long refundId, String refundNo,
                           BigDecimal amount, String providerId, Cancellation cancellation) {
        String metadata;
        try { metadata = json.writeValueAsString(cancellation); }
        catch (com.fasterxml.jackson.core.JsonProcessingException error) { throw new IllegalStateException(error); }
        return TransactionRetries.execute(transactions, status -> {
            db.update("INSERT INTO external_refund_attempts(refund_no,kind,order_id,payment_id,refund_id,channel," +
                    "out_trade_no,provider_transaction_id,amount,original_amount,metadata_json) VALUES(?,?,?,?,?,?,?,?,?,?,?) " +
                    "ON DUPLICATE KEY UPDATE refund_no=refund_no", refundNo, kind, payment.orderId(), payment.id(), refundId,
                    payment.channel(), payment.outTradeNo(), providerId == null ? "" : providerId, amount, payment.amount(), metadata);
            Attempt found = byNumber(refundNo);
            if (!kind.equals(found.kind()) || found.orderId() != payment.orderId() || found.paymentId() != payment.id()
                    || found.refundId() != refundId || amount.compareTo(found.amount()) != 0
                    || payment.amount().compareTo(found.originalAmount()) != 0
                    || !payment.channel().equals(found.channel()) || !payment.outTradeNo().equals(found.outTradeNo())
                    || !(providerId == null ? "" : providerId).equals(found.providerTransactionId())
                    || !sameMetadata(metadata, found.metadataJson()))
                throw new BizException(409, "退款请求号已用于其他操作");
            return found;
        });
    }

    public void confirmed(String refundNo) {
        TransactionRetries.executeWithoutResult(transactions, status -> db.update("UPDATE external_refund_attempts SET status='CONFIRMED',updated_at=NOW() " +
                "WHERE refund_no=? AND status='REQUESTED'", refundNo));
    }

    public void completeInTransaction(String refundNo) {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) throw new IllegalStateException("Refund requires a business transaction");
        markDone(refundNo);
    }

    public void markDone(String refundNo) {
        TransactionRetries.executeWithoutResult(transactions, status -> db.update("UPDATE external_refund_attempts SET status='DONE',updated_at=NOW() " +
                "WHERE refund_no=? AND status<>'DONE'", refundNo));
    }

    /** Locking current read sees committed intents without borrowing a second connection. */
    public Optional<Attempt> pendingCancellation(long orderId) {
        return TransactionRetries.execute(transactions, status -> db.query("SELECT * FROM external_refund_attempts WHERE order_id=? " +
                "AND kind='CANCEL' AND status<>'DONE' ORDER BY created_at LIMIT 1 FOR UPDATE", this::map, orderId).stream().findFirst());
    }

    public void requireNoCancellation(long orderId) {
        if (pendingCancellation(orderId).isPresent()) throw new BizException(409, "订单退款正在恢复处理中，暂不能继续履约");
    }

    public void requireRejectable(long refundId) {
        Boolean started = TransactionRetries.execute(transactions, status -> !db.query("SELECT refund_no FROM external_refund_attempts " +
                "WHERE refund_id=? AND kind='AFTER_SALES' LIMIT 1 FOR UPDATE", (rs, row) -> rs.getString(1), refundId).isEmpty());
        if (Boolean.TRUE.equals(started)) throw new BizException(409, "该申请已提交支付渠道退款，请重试审批或等待自动恢复，不能驳回");
    }

    public List<Attempt> pending(int limit) {
        return db.query("SELECT * FROM external_refund_attempts WHERE status IN ('REQUESTED','CONFIRMED') AND next_attempt_at<=NOW() " +
                "ORDER BY next_attempt_at,refund_no LIMIT ?", this::map, Math.clamp(limit, 1, 100));
    }

    public Optional<Attempt> byRefund(long refundId) {
        return db.query("SELECT * FROM external_refund_attempts WHERE refund_id=? AND kind='AFTER_SALES' LIMIT 1",
                this::map, refundId).stream().findFirst();
    }

    public Optional<Attempt> find(String number) {
        return db.query("SELECT * FROM external_refund_attempts WHERE refund_no=? FOR UPDATE", this::map, number).stream().findFirst();
    }

    public void defer(String refundNo) {
        TransactionRetries.executeWithoutResult(transactions, status -> db.update("UPDATE external_refund_attempts SET updated_at=NOW()," +
                "next_attempt_at=DATE_ADD(NOW(),INTERVAL LEAST(900,30*POW(2,LEAST(failure_count,5))) SECOND)," +
                "failure_count=LEAST(failure_count+1,1000) " +
                "WHERE refund_no=? AND status<>'DONE'", refundNo));
    }

    public Cancellation cancellation(Attempt attempt) {
        try { return json.readValue(attempt.metadataJson(), Cancellation.class); }
        catch (com.fasterxml.jackson.core.JsonProcessingException error) { throw new IllegalStateException(error); }
    }

    private boolean sameMetadata(String first, String second) {
        try { return json.readTree(first).equals(json.readTree(second)); }
        catch (com.fasterxml.jackson.core.JsonProcessingException error) { throw new IllegalStateException(error); }
    }

    private Attempt byNumber(String number) {
        return db.query("SELECT * FROM external_refund_attempts WHERE refund_no=? FOR UPDATE", this::map, number).getFirst();
    }
    private Attempt map(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        return new Attempt(rs.getString("refund_no"), rs.getString("kind"), rs.getLong("order_id"), rs.getLong("payment_id"),
                rs.getLong("refund_id"), rs.getString("channel"), rs.getString("out_trade_no"), rs.getString("provider_transaction_id"),
                rs.getBigDecimal("amount"), rs.getBigDecimal("original_amount"), rs.getString("metadata_json"), rs.getString("status"));
    }
}
