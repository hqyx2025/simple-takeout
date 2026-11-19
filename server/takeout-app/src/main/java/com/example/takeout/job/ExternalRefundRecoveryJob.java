package com.example.takeout.job;

import com.example.takeout.service.AfterSalesService;
import com.example.takeout.service.OrderService;
import com.example.takeout.service.ExternalRefundAttemptService;
import com.example.takeout.service.thirdparty.ExternalPaymentService;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Bounded recovery replays the original business action; order locks serialize replicas. */
@Component
public class ExternalRefundRecoveryJob {
    private final ExternalRefundAttemptService attempts;
    private final ObjectProvider<AfterSalesService> afterSales;
    private final ObjectProvider<OrderService> orders;
    private final ObjectProvider<ExternalPaymentService> payments;
    public ExternalRefundRecoveryJob(ExternalRefundAttemptService attempts, ObjectProvider<AfterSalesService> afterSales,
                                     ObjectProvider<OrderService> orders, ObjectProvider<ExternalPaymentService> payments) {
        this.attempts = attempts; this.afterSales = afterSales; this.orders = orders; this.payments = payments;
    }

    @Scheduled(scheduler = "paymentRecoveryScheduler", fixedDelayString="${takeout.payment.refund-recovery-ms:1000}",
            initialDelayString="${takeout.payment.refund-recovery-initial-ms:45000}")
    public void recover() {
        long deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(2);
        for (int batch = 0; batch < 10 && System.nanoTime() < deadline; batch++) {
        var pending = attempts.pending(20);
        if (pending.isEmpty()) return;
        for (var attempt : pending) {
            if (System.nanoTime() >= deadline) return;
            try {
                switch (attempt.kind()) {
                    case "AFTER_SALES" -> afterSales.getObject().recoverRefund(attempt);
                    case "CANCEL" -> orders.getObject().recoverCancellation(attempt);
                    case "LATE" -> payments.getObject().recoverLateRefund(attempt);
                    default -> throw new IllegalStateException("Unknown refund kind " + attempt.kind());
                }
            } catch (RuntimeException error) {
                try { attempts.defer(attempt.refundNo()); }
                catch (RuntimeException deferred) { error.addSuppressed(deferred); }
                org.slf4j.LoggerFactory.getLogger(ExternalRefundRecoveryJob.class)
                        .warn("External refund recovery pending refundNo={}", attempt.refundNo(), error);
            }
        }
        }
    }
}
