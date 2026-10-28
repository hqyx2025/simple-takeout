package com.example.takeout.dao;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import com.example.takeout.common.BizException;
import java.math.BigDecimal;
import java.util.List;

/** 售后订单条件流转及财务台账；调用者必须先持有订单锁。 */
@Repository
public class AfterSalesDao {
    private final JdbcTemplate jdbc;

    public AfterSalesDao(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public boolean markPending(long orderId, int escrow) {
        return jdbc.update("UPDATE orders SET status=6 WHERE id=? AND status=4 AND escrow_status=?",
                orderId, escrow) == 1;
    }

    public boolean finishOrder(long orderId, int originalEscrow, boolean full) {
        return jdbc.update("UPDATE orders SET status=?,escrow_status=? WHERE id=? AND status=6 AND escrow_status=?",
                full ? 6 : 4, full ? 2 : originalEscrow, orderId, originalEscrow) == 1;
    }

    /** 钱包按固定用户ID顺序加锁，兼容同一账号同时是买家和商家的情况。 */
    public void lockWallets(long customerId, long merchantId) {
        List<Long> users = jdbc.query("SELECT id FROM users WHERE id IN (?,?) ORDER BY id FOR UPDATE",
                (rs, row) -> rs.getLong(1), customerId, merchantId);
        if (!users.contains(customerId) || !users.contains(merchantId)) throw new BizException("退款账户不存在");
    }

    public void creditCustomer(long userId, BigDecimal amount) {
        if (jdbc.update("UPDATE users SET balance=balance+? WHERE id=?", amount, userId) != 1)
            throw new BizException("退款账户不存在");
    }

    public BigDecimal deductMerchant(long merchantId, BigDecimal amount) {
        BigDecimal balance = jdbc.queryForObject("SELECT balance FROM users WHERE id=? FOR UPDATE", BigDecimal.class, merchantId);
        if (balance == null) throw new BizException("商户账户不存在");
        BigDecimal deducted = amount.min(balance.max(BigDecimal.ZERO));
        if (deducted.signum() > 0 && jdbc.update("UPDATE users SET balance=balance-? WHERE id=? AND balance>=?",
                deducted, merchantId, deducted) != 1) throw new BizException("商户余额已变化");
        return deducted;
    }

    public void insertLedger(long refundId, long orderId, long merchantId, BigDecimal merchant,
                             BigDecimal deducted, BigDecimal debt, BigDecimal platform, String now) {
        jdbc.update("INSERT INTO after_sales_ledger(refund_id,order_id,merchant_id,merchant_amount,wallet_deducted," +
                "debt_amount,platform_amount,create_time) VALUES(?,?,?,?,?,?,?,?)",
                refundId, orderId, merchantId, merchant, deducted, debt, platform, now);
    }

    public void payMerchantSettlement(long orderId, long merchantId, BigDecimal net, String now) {
        BigDecimal balance = jdbc.queryForObject("SELECT balance FROM users WHERE id=? FOR UPDATE", BigDecimal.class, merchantId);
        if (balance == null) throw new BizException("商户账户不存在");
        List<Debt> debts = jdbc.query("SELECT id,refund_id,debt_amount FROM after_sales_ledger " +
                "WHERE merchant_id=? AND debt_amount>0 ORDER BY id FOR UPDATE",
                (rs, row) -> new Debt(rs.getLong("id"), rs.getLong("refund_id"), rs.getBigDecimal("debt_amount")), merchantId);
        BigDecimal available = net;
        for (Debt debt : debts) {
            if (available.signum() == 0) break;
            BigDecimal paid = available.min(debt.amount());
            jdbc.update("UPDATE after_sales_ledger SET debt_amount=debt_amount-?,debt_repaid=debt_repaid+? WHERE id=?",
                    paid, paid, debt.id());
            jdbc.update("INSERT INTO after_sales_debt_payments(settlement_order_id,refund_id,merchant_id,amount,create_time) " +
                    "VALUES(?,?,?,?,?)", orderId, debt.refundId(), merchantId, paid, now);
            available = available.subtract(paid);
        }
        if (available.signum() > 0) creditCustomer(merchantId, available);
        jdbc.update("INSERT INTO order_settlements(order_id,merchant_id,net_amount,debt_repaid,wallet_credited,settled_at) " +
                "VALUES(?,?,?,?,?,?)", orderId, merchantId, net, net.subtract(available), available, now);
    }

    private record Debt(long id, long refundId, BigDecimal amount) {}

    public BigDecimal netPaid(long userId) {
        return jdbc.queryForObject("SELECT COALESCE(SUM(CASE WHEN type='PAY' THEN amount WHEN type='REFUND' THEN -amount ELSE 0 END),0) " +
                "FROM payment_records WHERE user_id=? AND status='SUCCESS'", BigDecimal.class, userId);
    }

    public int countLedger(long merchantId) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM after_sales_ledger WHERE merchant_id=?", Integer.class, merchantId);
    }

    public BigDecimal debtAmount(long merchantId) {
        return jdbc.queryForObject("SELECT COALESCE(SUM(debt_amount),0) FROM after_sales_ledger WHERE merchant_id=?",
                BigDecimal.class, merchantId);
    }

    public List<LedgerEntry> ledger(long merchantId, int limit, long offset) {
        return jdbc.query("SELECT * FROM after_sales_ledger WHERE merchant_id=? ORDER BY id DESC LIMIT ? OFFSET ?",
                (rs, row) -> new LedgerEntry(rs.getLong("refund_id"), rs.getLong("order_id"),
                        rs.getBigDecimal("merchant_amount"), rs.getBigDecimal("wallet_deducted"),
                        rs.getBigDecimal("debt_amount"), rs.getBigDecimal("platform_amount"), rs.getString("create_time")),
                merchantId, limit, offset);
    }

    public record LedgerEntry(long refundId, long orderId, BigDecimal merchantAmount, BigDecimal walletDeducted,
                              BigDecimal debtAmount, BigDecimal platformAmount, String createTime) {}
}
