package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.security.PasswordUtil;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Deletes contact data, retaining pseudonymous order and financial facts. */
@Service
public class AccountClosureService {
    private final UserDao users;
    private final JdbcTemplate jdbc;
    private final PersonalDataCrypto crypto;

    public AccountClosureService(UserDao users, JdbcTemplate jdbc, PersonalDataCrypto crypto) {
        this.users = users; this.jdbc = jdbc; this.crypto = crypto;
    }

    @Transactional
    public void close(long userId, String password) {
        users.lockActiveCustomerLifecycle(userId);
        // Match payment/refund lock order. The lifecycle guard prevents new orders or appeals
        // while existing order transactions finish before the wallet row is acquired.
        jdbc.queryForList("SELECT id FROM orders WHERE user_id=? ORDER BY id FOR UPDATE", Long.class, userId);
        var user = users.findByIdForUpdate(userId).orElseThrow(() -> new BizException(401, "用户不存在"));
        if (user.status() != 1 || user.role() != 0) throw new BizException(403, "仅启用的用户账号可自行注销");
        if (password == null || password.length() > 64 || !PasswordUtil.matches(password, user.password())) {
            throw new BizException(400, "当前密码不正确");
        }
        if (jdbc.queryForObject("SELECT balance FROM users WHERE id=? FOR UPDATE", java.math.BigDecimal.class, userId).signum() != 0) {
            throw new BizException(409, "余额未结清，请先处理余额后再注销");
        }
        // A delivered but unsettled order and a refund still in progress are active obligations.
        if (exists("SELECT EXISTS(SELECT 1 FROM orders WHERE user_id=? AND NOT " +
                "((status=5 AND (escrow_status=2 OR (escrow_status=0 AND (pay_time IS NULL OR pay_time='')))) " +
                "OR (status=4 AND escrow_status=1) OR (status=6 AND escrow_status=2)))", userId)) {
            throw new BizException(409, "还有未完成订单或待结算资金，请处理完成后再注销");
        }
        if (exists("SELECT EXISTS(SELECT 1 FROM refund_records WHERE user_id=? AND status NOT IN ('REFUNDED','REJECTED'))", userId)
                || exists("SELECT EXISTS(SELECT 1 FROM payment_transactions WHERE user_id=? AND status='PENDING')", userId)
                || exists("SELECT EXISTS(SELECT 1 FROM external_refund_attempts a JOIN orders o ON o.id=a.order_id " +
                "WHERE o.user_id=? AND a.status<>'DONE')", userId)) {
            throw new BizException(409, "支付或售后仍在处理中，请完成后再注销");
        }
        users.revokeSessions(userId);
        String tombstone = "!" + userId;
        jdbc.update("UPDATE users SET username=?,avatar='',phone=?,phone_encrypted=?,phone_lookup=?,phone_length=?," +
                        "email=NULL,password='',payment_password_hash=NULL,status=0,can_create=0,can_read=0,can_update=0,can_delete=0 WHERE id=?",
                "closed_" + userId + "_" + java.util.UUID.randomUUID().toString().replace("-", ""),
                crypto.phoneToken(tombstone), crypto.encrypt(tombstone, "users.phone"), crypto.hash("phone:exact", tombstone),
                tombstone.length(), userId);
        for (String table : java.util.List.of("addresses", "cart_items", "favorites", "coupons", "bank_cards", "push_tokens",
                "user_contact_verifications", "user_phone_search")) {
            jdbc.update("DELETE FROM " + table + " WHERE user_id=?", userId);
        }
        String anonymousAddress = crypto.encrypt("{\"addressId\":0,\"name\":\"已注销用户\",\"phone\":\"\",\"detail\":\"\"}", "orders.address");
        jdbc.update("UPDATE orders SET address=?,remark='' WHERE user_id=?", anonymousAddress, userId);
        jdbc.update("UPDATE reviews SET user_name='已注销用户',anonymous=1 WHERE user_id=?", userId);
        jdbc.update("UPDATE account_lifecycle_guards SET closed_at=NOW() WHERE user_id=?", userId);
    }

    private boolean exists(String sql, long userId) {
        return Boolean.TRUE.equals(jdbc.queryForObject(sql, Boolean.class, userId));
    }
}
