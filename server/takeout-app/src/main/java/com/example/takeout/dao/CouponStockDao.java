package com.example.takeout.dao;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.ArrayList;
import java.util.List;

/** 每张券一个持久名额，避免所有领取请求争用同一个库存计数行。 */
@Repository
public class CouponStockDao {
    public static final int CAMPAIGN_QUOTA = 5;
    private final JdbcTemplate jdbc;

    public CouponStockDao(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    /** 启动事务中幂等补名额；历史已发出的券也计入总量，已有名额永不重置。 */
    public void initialize(String campaign, double threshold, double amount) {
        Long issued = jdbc.queryForObject("SELECT GREATEST(" +
                "(SELECT COUNT(*) FROM coupons WHERE source = 'claim' AND threshold = ? AND amount = ?)," +
                "(SELECT COUNT(*) FROM user_coupons WHERE threshold = ? AND amount = ?))", Long.class,
                threshold, amount, threshold, amount);
        List<Object[]> slots = new ArrayList<>();
        for (int slot = 1; slot <= CAMPAIGN_QUOTA; slot++) {
            slots.add(new Object[]{campaign, slot, issued != null && slot <= issued ? 0L : null});
        }
        jdbc.batchUpdate("INSERT IGNORE INTO coupon_campaign_stock(campaign_name, slot_no, claimed_user_id) " +
                "VALUES(?,?,?)", slots);
    }

    /** 售罄后的请求走只读快速拒绝；最终库存裁决仍以 reserve 为准。 */
    public boolean hasAvailable(String campaign) {
        return Boolean.TRUE.equals(jdbc.queryForObject("SELECT EXISTS(SELECT 1 FROM coupon_campaign_stock " +
                "WHERE campaign_name = ? AND claimed_user_id IS NULL)", Boolean.class, campaign));
    }

    /** 必须与领取台账、发券共用事务；繁忙名额跳过，不排队，也不提前宣告成功。 */
    public boolean reserve(String campaign, long userId) {
        List<Integer> slots = jdbc.query("SELECT slot_no FROM coupon_campaign_stock " +
                        "WHERE campaign_name = ? AND claimed_user_id IS NULL ORDER BY slot_no LIMIT 1 " +
                        "FOR UPDATE SKIP LOCKED", (rs, row) -> rs.getInt(1), campaign);
        if (slots.isEmpty()) return false;
        return jdbc.update("UPDATE coupon_campaign_stock SET claimed_user_id = ? " +
                "WHERE campaign_name = ? AND slot_no = ? AND claimed_user_id IS NULL",
                userId, campaign, slots.getFirst()) == 1;
    }
}
