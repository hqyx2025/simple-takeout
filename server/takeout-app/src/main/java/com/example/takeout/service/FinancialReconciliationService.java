package com.example.takeout.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/** Read-only checks against business facts; discrepancies never cause automatic wallet adjustments. */
@Service
public class FinancialReconciliationService {
    private final JdbcTemplate db;
    private final TransactionTemplate tx;
    public FinancialReconciliationService(JdbcTemplate db, TransactionTemplate tx) { this.db = db; this.tx = tx; }

    public void scanBatch() {
        scan("ORDERS");
        scan("WALLETS");
    }

    private void scan(String task) {
        tx.executeWithoutResult(status -> {
            db.update("INSERT IGNORE INTO financial_reconciliation_progress(task,scan_date) VALUES(?,CURRENT_DATE)", task);
            var cursor = db.queryForMap("SELECT last_id,complete,scan_date=CURRENT_DATE same_day "
                    + "FROM financial_reconciliation_progress WHERE task=? FOR UPDATE", task);
            boolean sameDay = number(cursor, "same_day") == 1;
            if (sameDay && number(cursor, "complete") == 1) return;
            long after = sameDay ? number(cursor, "last_id") : 0;
            List<Map<String,Object>> rows = task.equals("ORDERS") ? orders(after) : wallets(after);
            for (var row : rows) {
                long id = number(row, "id");
                if (task.equals("ORDERS")) {
                    long count = number(row, "pay_count");
                    long businessPayments = count - number(row, "late_count");
                    BigDecimal expectedRefunds = money(row,"refund_facts").add(money(row,"pay_amount")
                            .multiply(BigDecimal.valueOf(number(row,"late_count") + number(row,"cancelled_paid"))));
                    boolean valid = businessPayments >= 0 && businessPayments <= 1
                            && money(row,"paid").compareTo(money(row,"pay_amount").multiply(BigDecimal.valueOf(count))) == 0
                            && money(row,"refunded").compareTo(money(row,"paid")) <= 0
                            && expectedRefunds.compareTo(money(row,"refunded")) == 0
                            && money(row,"settled").compareTo(money(row,"credited").add(money(row,"debt_repaid"))) == 0
                            && money(row,"external_paid").compareTo(money(row,"provider_paid")) == 0
                            && (number(row,"has_paid_time") == 0 || businessPayments == 1);
                    record("ORDER_MONEY", id, valid, row);
                } else {
                    record("WALLET_BALANCE", id, money(row,"balance").signum() >= 0
                            && money(row,"balance").compareTo(money(row,"observed_balance")) == 0, row);
                }
            }
            long last = rows.isEmpty() ? after : number(rows.getLast(), "id");
            db.update("UPDATE financial_reconciliation_progress SET scan_date=CURRENT_DATE,last_id=?,complete=? WHERE task=?",
                    last, rows.size() < 500, task);
        });
    }

    private List<Map<String,Object>> orders(long after) {
        return db.queryForList("SELECT o.id,o.pay_amount,COALESCE(o.pay_time,'')<>'' has_paid_time,"
                + "(o.status=5 AND o.escrow_status=2 AND COALESCE(o.pay_time,'')<>'') cancelled_paid,"
                + "(SELECT COUNT(*) FROM payment_records p WHERE p.order_id=o.id AND p.type='PAY' AND p.status='SUCCESS') pay_count,"
                + "COALESCE((SELECT SUM(amount) FROM payment_records p WHERE p.order_id=o.id AND p.type='PAY' AND p.status='SUCCESS'),0) paid,"
                + "COALESCE((SELECT SUM(amount) FROM payment_records p WHERE p.order_id=o.id AND p.type='PAY' AND p.channel<>'BALANCE' AND p.status='SUCCESS'),0) external_paid,"
                + "COALESCE((SELECT SUM(amount) FROM payment_transactions p WHERE p.order_id=o.id AND p.status IN ('SUCCESS','REFUNDED','LATE_REFUNDED')),0) provider_paid,"
                + "(SELECT COUNT(*) FROM payment_transactions p WHERE p.order_id=o.id AND p.status='LATE_REFUNDED') late_count,"
                + "COALESCE((SELECT SUM(amount) FROM payment_records p WHERE p.order_id=o.id AND p.type='REFUND' AND p.status='SUCCESS'),0) refunded,"
                + "COALESCE((SELECT SUM(amount) FROM refund_records r WHERE r.order_id=o.id AND r.status='REFUNDED'),0) refund_facts,"
                + "COALESCE(s.net_amount,0) settled,COALESCE(s.wallet_credited,0) credited,COALESCE(s.debt_repaid,0) debt_repaid "
                + "FROM orders o LEFT JOIN order_settlements s ON s.order_id=o.id WHERE o.id>? ORDER BY o.id LIMIT 500", after);
    }
    private List<Map<String,Object>> wallets(long after) {
        return db.queryForList("SELECT u.id,u.balance,COALESCE((SELECT m.balance_after FROM wallet_movements m "
                + "WHERE m.user_id=u.id ORDER BY m.id DESC LIMIT 1),u.balance) observed_balance "
                + "FROM users u WHERE u.id>? ORDER BY u.id LIMIT 500", after);
    }
    private void record(String type, long id, boolean valid, Map<String,Object> evidence) {
        if (valid) {
            db.update("UPDATE financial_reconciliation_issues SET resolved_at=NOW() WHERE check_type=? AND entity_id=? AND resolved_at IS NULL", type, id);
        } else {
            db.update("INSERT INTO financial_reconciliation_issues(check_type,entity_id,evidence) VALUES(?,?,?) "
                    + "ON DUPLICATE KEY UPDATE evidence=VALUES(evidence),last_seen=NOW(),resolved_at=NULL", type, id, evidence.toString());
        }
    }
    public List<Map<String,Object>> issues(int limit) {
        return db.queryForList("SELECT check_type,entity_id,evidence,first_seen,last_seen,resolved_at "
                + "FROM financial_reconciliation_issues ORDER BY resolved_at IS NOT NULL,last_seen DESC LIMIT ?", Math.clamp(limit,1,100));
    }
    private static long number(Map<String,Object> row, String key) { return ((Number) row.get(key)).longValue(); }
    private static BigDecimal money(Map<String,Object> row, String key) { return new BigDecimal(row.get(key).toString()); }
}
