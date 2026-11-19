package com.example.takeout.config;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class FinancialHealthMetrics {
    private record Snapshot(double issues, double paymentAge, double refundAge, double available) { }
    private volatile Snapshot snapshot = new Snapshot(Double.NaN,Double.NaN,Double.NaN,0);
    private final JdbcTemplate db;
    public FinancialHealthMetrics(JdbcTemplate db, MeterRegistry registry) {
        this.db=db;
        Gauge.builder("takeout.reconciliation.open",this,s->s.snapshot.issues()).register(registry);
        Gauge.builder("takeout.payment.pending.oldest.seconds",this,s->s.snapshot.paymentAge()).register(registry);
        Gauge.builder("takeout.refund.pending.oldest.seconds",this,s->s.snapshot.refundAge()).register(registry);
        Gauge.builder("takeout.financial.collector.available",this,s->s.snapshot.available()).register(registry);
    }
    @Scheduled(fixedDelay=15000,initialDelay=60000)
    public void refresh() {
        try {
            snapshot=db.queryForObject("SELECT (SELECT COUNT(*) FROM financial_reconciliation_issues WHERE resolved_at IS NULL) issues,"
                    +"GREATEST(COALESCE((SELECT TIMESTAMPDIFF(SECOND,MIN(create_time),NOW()) FROM payment_transactions WHERE status='PENDING'),0),0) payment_age,"
                    +"GREATEST(COALESCE((SELECT TIMESTAMPDIFF(SECOND,MIN(created_at),NOW()) FROM external_refund_attempts WHERE status<>'DONE'),0),0) refund_age",
                    (row,index)->new Snapshot(row.getDouble("issues"),row.getDouble("payment_age"),row.getDouble("refund_age"),1));
        } catch(org.springframework.dao.DataAccessException failure) {
            snapshot=new Snapshot(Double.NaN,Double.NaN,Double.NaN,0);
        }
    }
}
