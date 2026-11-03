package com.example.takeout.erp;

import org.springframework.boot.sql.init.dependency.DependsOnDatabaseInitialization;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.Map;

/** 增量补充业务单号；历史单据保留原 ID，用 L 命名空间避免与新雪花编号重合。 */
@Component
@DependsOnDatabaseInitialization
public class ErpDocumentNumberMigration {
    public ErpDocumentNumberMigration(JdbcTemplate db) {
        for (var entry : Map.of("erp_purchases", "CG", "erp_receipts", "RK",
                "erp_adjustments", "TZ", "erp_payments", "FK").entrySet()) {
            String table = entry.getKey();
            var columns = db.queryForList("SELECT IS_NULLABLE FROM information_schema.COLUMNS "
                    + "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME='document_no'", table);
            if (columns.isEmpty()) {
                db.execute("ALTER TABLE " + table + " ADD COLUMN document_no VARCHAR(32) NULL");
            }
            if (columns.isEmpty() || "YES".equals(columns.getFirst().get("IS_NULLABLE"))) {
                db.update("UPDATE " + table + " SET document_no=CONCAT(?,id) WHERE document_no IS NULL",
                        entry.getValue() + "-L-");
                db.execute("ALTER TABLE " + table + " MODIFY COLUMN document_no VARCHAR(32) NOT NULL");
            }
            Integer indexes = db.queryForObject("SELECT COUNT(*) FROM information_schema.STATISTICS "
                    + "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND INDEX_NAME=?", Integer.class,
                    table, "uk_" + table + "_document_no");
            if (indexes == null || indexes == 0) {
                db.execute("ALTER TABLE " + table + " ADD UNIQUE KEY uk_" + table + "_document_no(document_no)");
            }
        }
    }
}
