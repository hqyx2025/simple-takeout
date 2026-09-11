package com.example.takeout.config;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * 已有数据库的幂等表结构升级。
 * schema.sql 使用 CREATE TABLE IF NOT EXISTS，不会给已存在的表追加新列；
 * 这里在启动时检查并补齐缺列，保证老库升级后可直接运行。
 */
@Component
public class SchemaMigration implements ApplicationRunner {

    private final JdbcTemplate jdbc;

    public SchemaMigration(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public void run(ApplicationArguments args) {
        addColumnIfMissing("reviews", "order_id", "BIGINT NOT NULL DEFAULT 0");
        addColumnIfMissing("reviews", "images", "TEXT");
        addColumnIfMissing("reviews", "anonymous", "INT NOT NULL DEFAULT 0");
        addColumnIfMissing("reviews", "reply", "VARCHAR(512) DEFAULT ''");
        addColumnIfMissing("reviews", "reply_time", "VARCHAR(32) DEFAULT ''");
        // 四端改造：订单的骑手分配与出餐时间
        addColumnIfMissing("orders", "rider_id", "BIGINT NOT NULL DEFAULT 0");
        addColumnIfMissing("orders", "ready_time", "VARCHAR(32) DEFAULT ''");
        // 预约送达时间（空=立即送达）
        addColumnIfMissing("orders", "expect_time", "VARCHAR(32) DEFAULT ''");
        // 待付款支付模型：订单与所用优惠券解绑时需要用 coupon_id 释放优惠券
        addColumnIfMissing("orders", "coupon_id", "BIGINT NOT NULL DEFAULT 0");
        // 多规格 SKU：购物车按 (用户,菜品,规格) 唯一
        addColumnIfMissing("cart_items", "spec_id", "BIGINT NOT NULL DEFAULT 0");
        rebuildCartUniqueKey();
    }

    /**
     * 老库的 uk_cart_user_goods(user_id, goods_id) 不允许同一菜品加入两个规格，
     * 这里幂等地替换为 uk_cart_user_goods_spec(user_id, goods_id, spec_id)。
     */
    private void rebuildCartUniqueKey() {
        if (indexExists("cart_items", "uk_cart_user_goods_spec")) {
            return;
        }
        if (indexExists("cart_items", "uk_cart_user_goods")) {
            jdbc.execute("ALTER TABLE cart_items DROP INDEX uk_cart_user_goods");
        }
        jdbc.execute("ALTER TABLE cart_items ADD UNIQUE KEY uk_cart_user_goods_spec (user_id, goods_id, spec_id)");
    }

    private boolean indexExists(String table, String indexName) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM information_schema.STATISTICS " +
                        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?",
                Integer.class, table, indexName);
        return count != null && count > 0;
    }

    private void addColumnIfMissing(String table, String column, String definition) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM information_schema.COLUMNS " +
                        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
                Integer.class, table, column);
        if (count == null || count == 0) {
            jdbc.execute("ALTER TABLE " + table + " ADD COLUMN " + column + " " + definition);
        }
    }
}
