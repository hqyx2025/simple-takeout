package com.example.takeout.dao;

import com.example.takeout.model.UserCoupon;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;

/** 优惠券领取台账。 */
@Repository
public class UserCouponDao {

    private static final RowMapper<UserCoupon> MAPPER = (rs, i) -> new UserCoupon(
            rs.getLong("id"),
            rs.getLong("user_id"),
            rs.getLong("store_id"),
            rs.getString("name"),
            rs.getDouble("threshold"),
            rs.getDouble("amount"),
            rs.getString("claim_time"),
            rs.getString("expire_time")
    );

    private final JdbcTemplate jdbc;

    public UserCouponDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public boolean exists(long userId, long storeId, String name) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM user_coupons WHERE user_id = ? AND store_id = ? AND name = ?",
                Integer.class, userId, storeId, name);
        return count != null && count > 0;
    }

    public void insert(long userId, long storeId, String name, double threshold, double amount,
                       String claimTime, String expireTime) {
        jdbc.update("INSERT INTO user_coupons(user_id, store_id, name, threshold, amount, claim_time, expire_time) VALUES(?,?,?,?,?,?,?)",
                userId, storeId, name, threshold, amount, claimTime, expireTime);
    }

    public List<UserCoupon> listByUser(long userId) {
        return jdbc.query("SELECT * FROM user_coupons WHERE user_id = ? ORDER BY id DESC", MAPPER, userId);
    }
}
