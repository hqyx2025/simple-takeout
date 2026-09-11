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
