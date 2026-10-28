package com.example.takeout.config;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.stereotype.Component;
import java.sql.SQLException;

/** 独立售后迁移，先于通用旧库迁移执行；启动失败时不带缺列继续服务。 */
@Component
@Order(0)
public class AfterSalesSchemaMigration implements ApplicationRunner {
    private final JdbcTemplate jdbc;
    public AfterSalesSchemaMigration(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @Override
    public void run(ApplicationArguments args) {
        new ResourceDatabasePopulator(new ClassPathResource("after-sales-schema.sql")).execute(jdbc.getDataSource());
        for (String[] column : new String[][] {
                {"reason_type", "VARCHAR(32) NOT NULL DEFAULT 'OTHER'"},
                {"request_key", "VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin DEFAULT NULL"},
                {"evidence_images", "TEXT"}, {"merchant_evidence_images", "TEXT"},
                {"merchant_response", "VARCHAR(1000) NOT NULL DEFAULT ''"},
                {"appeal_count", "INT NOT NULL DEFAULT 0"},
                {"appeal_reason", "VARCHAR(255) NOT NULL DEFAULT ''"}, {"appeal_images", "TEXT"},
                {"original_escrow", "INT NOT NULL DEFAULT 0"}, {"settled_before", "TINYINT NOT NULL DEFAULT 0"},
                {"merchant_amount", "DECIMAL(10,2) NOT NULL DEFAULT 0"},
                {"platform_amount", "DECIMAL(10,2) NOT NULL DEFAULT 0"}, {"refund_time", "DATETIME NULL"}}) {
            addColumn(column[0], column[1]);
        }
        addIndex("uk_refund_order_request", "UNIQUE", "(order_id,request_key)");
        addIndex("idx_refund_status_page", "", "(status,id)");
        // 老政策只允许未结算退款；回填历史成功事实，不改变任何资金余额。
        jdbc.update("UPDATE refund_records r JOIN orders o ON o.id=r.order_id " +
                "SET r.merchant_amount=LEAST(r.amount,GREATEST(o.pay_amount-o.delivery_fee,0))," +
                "r.platform_amount=r.amount-LEAST(r.amount,GREATEST(o.pay_amount-o.delivery_fee,0))," +
                "r.refund_time=CASE WHEN r.process_time REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' " +
                "THEN STR_TO_DATE(r.process_time,'%Y-%m-%d %H:%i:%s') ELSE NULL END " +
                "WHERE r.status='REFUNDED' AND r.refund_time IS NULL AND r.merchant_amount=0 AND r.platform_amount=0");
    }

    private void addColumn(String name, String definition) {
        if (hasColumn(name)) return;
        try { jdbc.execute("ALTER TABLE refund_records ADD COLUMN " + name + " " + definition); }
        catch (org.springframework.dao.DataAccessException error) {
            if (!(error.getMostSpecificCause() instanceof SQLException sql) || sql.getErrorCode() != 1060 || !hasColumn(name)) throw error;
        }
    }

    private void addIndex(String name, String kind, String columns) {
        if (hasIndex(name)) return;
        try { jdbc.execute("ALTER TABLE refund_records ADD " + kind + " INDEX " + name + " " + columns); }
        catch (org.springframework.dao.DataAccessException error) {
            if (!(error.getMostSpecificCause() instanceof SQLException sql) || sql.getErrorCode() != 1061 || !hasIndex(name)) throw error;
        }
    }

    private boolean hasIndex(String name) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.STATISTICS " +
                "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='refund_records' AND INDEX_NAME=?", Integer.class, name);
        return count != null && count > 0;
    }

    private boolean hasColumn(String name) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.COLUMNS " +
                "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='refund_records' AND COLUMN_NAME=?", Integer.class, name);
        return count != null && count > 0;
    }
}
