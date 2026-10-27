-- ERP owns these tables in a separate database; no access to app tables.
-- Only non-food operating supplies; quantities use each material's immutable base unit.
CREATE TABLE IF NOT EXISTS erp_suppliers (
 id BIGINT AUTO_INCREMENT PRIMARY KEY, store_id BIGINT NOT NULL, name VARCHAR(100) NOT NULL,
 contact VARCHAR(100) NOT NULL, enabled BOOLEAN NOT NULL DEFAULT TRUE, KEY idx_supplier_store(store_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_materials (
 id BIGINT AUTO_INCREMENT PRIMARY KEY, store_id BIGINT NOT NULL, name VARCHAR(100) NOT NULL,
 unit VARCHAR(16) NOT NULL, balance DECIMAL(18,3) NOT NULL DEFAULT 0,
 UNIQUE KEY uk_material_name(store_id,name), KEY idx_material_store(store_id,id), CHECK(balance >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_purchases (
 id BIGINT AUTO_INCREMENT PRIMARY KEY, store_id BIGINT NOT NULL, supplier_id BIGINT NOT NULL,
 status VARCHAR(16) NOT NULL DEFAULT 'DRAFT', ordered_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
 payable DECIMAL(18,2) NOT NULL DEFAULT 0, paid DECIMAL(18,2) NOT NULL DEFAULT 0,
 operator_id BIGINT NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY idx_purchase_store(store_id,id), KEY idx_purchase_supplier(store_id,supplier_id,id), CHECK(paid >= 0 AND paid <= payable)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_purchase_lines (
 id BIGINT AUTO_INCREMENT PRIMARY KEY, purchase_id BIGINT NOT NULL, material_id BIGINT NOT NULL,
 quantity DECIMAL(18,3) NOT NULL, received DECIMAL(18,3) NOT NULL DEFAULT 0,
 unit_price DECIMAL(18,4) NOT NULL, purchase_unit VARCHAR(16) NOT NULL, factor DECIMAL(18,3) NOT NULL,
 KEY idx_line_purchase(purchase_id,id), UNIQUE KEY uk_purchase_material(purchase_id,material_id),
 CHECK(quantity > 0 AND received >= 0 AND received <= quantity AND factor > 0 AND unit_price > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_receipts (
 id BIGINT AUTO_INCREMENT PRIMARY KEY, store_id BIGINT NOT NULL, purchase_id BIGINT NOT NULL,
 operator_id BIGINT NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY idx_receipt_store(store_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_ledger (
 id BIGINT AUTO_INCREMENT PRIMARY KEY, store_id BIGINT NOT NULL, material_id BIGINT NOT NULL,
 source_type VARCHAR(16) NOT NULL, source_id BIGINT NOT NULL, delta DECIMAL(18,3) NOT NULL,
 before_qty DECIMAL(18,3) NOT NULL, after_qty DECIMAL(18,3) NOT NULL, unit VARCHAR(16) NOT NULL,
 reason VARCHAR(255) NOT NULL, operator_id BIGINT NOT NULL, reversal_of BIGINT DEFAULT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE KEY uk_ledger_source(source_type,source_id,material_id),
 UNIQUE KEY uk_ledger_reversal(reversal_of), KEY idx_ledger_store(store_id,id), CHECK(after_qty >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_adjustments (
 id BIGINT AUTO_INCREMENT PRIMARY KEY, store_id BIGINT NOT NULL, material_id BIGINT NOT NULL,
 kind VARCHAR(16) NOT NULL, book_qty DECIMAL(18,3) NOT NULL, actual_qty DECIMAL(18,3) NOT NULL,
 reason VARCHAR(255) NOT NULL, status VARCHAR(16) NOT NULL DEFAULT 'SUBMITTED',
 operator_id BIGINT NOT NULL, reviewer_id BIGINT DEFAULT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY idx_adjust_store(store_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_payments (
 id BIGINT AUTO_INCREMENT PRIMARY KEY, store_id BIGINT NOT NULL, purchase_id BIGINT NOT NULL,
 amount DECIMAL(18,2) NOT NULL, reference VARCHAR(100) NOT NULL, operator_id BIGINT NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE KEY uk_payment_reference(store_id,reference),
 KEY idx_payment_purchase(purchase_id,id), KEY idx_payment_store(store_id,id), CHECK(amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_requests (
 store_id BIGINT NOT NULL, request_key VARCHAR(128) COLLATE utf8mb4_bin NOT NULL, request_hash CHAR(64) NOT NULL,
 result_json TEXT DEFAULT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(store_id,request_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_audit (
 id BIGINT AUTO_INCREMENT PRIMARY KEY, store_id BIGINT NOT NULL, operator_id BIGINT NOT NULL,
 action VARCHAR(40) NOT NULL, document_id BIGINT NOT NULL, detail VARCHAR(255) NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY idx_audit_store(store_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_event_inbox (
 event_id BIGINT PRIMARY KEY, event_type VARCHAR(64) NOT NULL, order_id BIGINT NOT NULL,
 payload JSON NOT NULL, received_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY idx_event_order(order_id,event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS erp_receipt_reversals (
 receipt_id BIGINT PRIMARY KEY, store_id BIGINT NOT NULL, operator_id BIGINT NOT NULL,
 reason VARCHAR(255) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY idx_receipt_reversal_store(store_id,receipt_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
