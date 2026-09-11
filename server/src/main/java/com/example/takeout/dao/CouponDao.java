package com.example.takeout.dao;

import com.example.takeout.model.Coupon;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * 优惠券数据访问
 */
@Repository
public class CouponDao {

    private static final RowMapper<Coupon> MAPPER = (rs, i) -> new Coupon(
            rs.getLong("id"),
            rs.getLong("user_id"),
            rs.getLong("store_id"),
            rs.getString("name"),
            rs.getDouble("threshold"),
            rs.getDouble("amount"),
            rs.getInt("status"),
            rs.getString("expire_time"),
            rs.getString("source"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public CouponDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Coupon> listByUser(long userId) {
        return jdbc.query("SELECT * FROM coupons WHERE user_id = ? ORDER BY status, id DESC", MAPPER, userId);
    }

    public long insert(long userId, long storeId, String name, double threshold, double amount,
                       String expireTime, String source, String now) {
        jdbc.update("INSERT INTO coupons(user_id, store_id, name, threshold, amount, status, expire_time, source, create_time) VALUES(?,?,?,?,?,?,?,?,?)",
                userId, storeId, name, threshold, amount, 0, expireTime, source, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    /**
     * 核销优惠券（条件更新，防并发重复核销）：
     * 返回 false 表示该券已被核销/不可用，由调用方抛业务异常并回滚整单。
     */
    public boolean markUsed(long id) {
        return jdbc.update("UPDATE coupons SET status = 1 WHERE id = ? AND status = 0", id) == 1;
    }

    /** 过期券清理：把已过期的未使用券标记为已失效（status=2）。 */
    public int expireOutdated(String now) {
        return jdbc.update("UPDATE coupons SET status = 2 WHERE status = 0 AND expire_time <> '' AND expire_time < ?", now);
    }
}
