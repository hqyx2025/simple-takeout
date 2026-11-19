package com.example.takeout.job;

import com.example.takeout.service.thirdparty.ExternalPaymentService;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.List;

/** Claim before network I/O; a lost callback is recovered with the original provider trade number. */
@Component
public class PendingPaymentRecoveryJob {
    private final JdbcTemplate db;
    private final TransactionTemplate tx;
    private final ExternalPaymentService payments;
    public PendingPaymentRecoveryJob(JdbcTemplate db, TransactionTemplate tx, ExternalPaymentService payments) {
        this.db = db; this.tx = tx; this.payments = payments;
    }
    @Scheduled(scheduler="paymentRecoveryScheduler", fixedDelayString="${takeout.payment.query-recovery-ms:1000}", initialDelay=45000)
    public void recover() {
        long deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(2);
        for (int count=0; count<100 && System.nanoTime()<deadline; count++) {
            List<Long> ids = tx.execute(status -> {
                var found = db.queryForList("SELECT p.order_id FROM payment_transactions p LEFT JOIN order_background_retries r "
                        + "ON r.order_id=p.order_id AND r.task='PAYMENT' WHERE p.status='PENDING' "
                        + "AND p.create_time<DATE_FORMAT(DATE_SUB(NOW(),INTERVAL 30 SECOND),'%Y-%m-%d %H:%i:%s') "
                        + "AND (r.next_attempt_at IS NULL OR r.next_attempt_at<=NOW()) ORDER BY p.id LIMIT 1 FOR UPDATE SKIP LOCKED", Long.class);
                for (long id : found) db.update("INSERT INTO order_background_retries(order_id,task,failure_count,next_attempt_at) "
                        + "VALUES(?,'PAYMENT',0,DATE_ADD(NOW(),INTERVAL 30 SECOND)) ON DUPLICATE KEY UPDATE "
                        + "next_attempt_at=DATE_ADD(NOW(),INTERVAL 30 SECOND)", id);
                return found;
            });
            if (ids == null || ids.isEmpty()) return;
            long id = ids.getFirst();
            try { payments.refreshPayment(id); }
            catch (RuntimeException failure) {
                db.update("UPDATE order_background_retries SET failure_count=LEAST(failure_count+1,10),"
                        + "next_attempt_at=TIMESTAMPADD(SECOND,LEAST(300,5*POW(2,LEAST(failure_count,6))),NOW()) "
                        + "WHERE order_id=? AND task='PAYMENT'", id);
                org.slf4j.LoggerFactory.getLogger(getClass()).warn("未决支付查询等待恢复 orderId={} error={}", id, failure.getClass().getSimpleName());
            }
        }
    }
}
