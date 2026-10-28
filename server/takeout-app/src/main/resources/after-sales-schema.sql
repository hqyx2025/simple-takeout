-- 独立售后DDL：可在全新库直接初始化，也可由迁移为旧表补列。
CREATE TABLE IF NOT EXISTS refund_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    merchant_id BIGINT NOT NULL,
    reason_type VARCHAR(32) NOT NULL DEFAULT 'OTHER',
    reason VARCHAR(255) DEFAULT '',
    request_key VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin DEFAULT NULL,
    amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    apply_time VARCHAR(32) NOT NULL,
    process_time VARCHAR(32) DEFAULT '',
    reject_reason VARCHAR(255) DEFAULT '',
    evidence_images TEXT,
    merchant_evidence_images TEXT,
    merchant_response VARCHAR(1000) NOT NULL DEFAULT '',
    appeal_count INT NOT NULL DEFAULT 0,
    appeal_reason VARCHAR(255) NOT NULL DEFAULT '',
    appeal_images TEXT,
    original_escrow INT NOT NULL DEFAULT 0,
    settled_before TINYINT NOT NULL DEFAULT 0,
    merchant_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    platform_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    refund_time DATETIME NULL,
    KEY idx_refund_order(order_id),
    UNIQUE KEY uk_refund_order_request(order_id,request_key),
    KEY idx_refund_status_page(status,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS refund_apply_requests (
    order_id BIGINT NOT NULL,
    request_key VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin NOT NULL,
    refund_id BIGINT NOT NULL,
    create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(order_id,request_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS after_sales_ledger (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    refund_id BIGINT NOT NULL,
    order_id BIGINT NOT NULL,
    merchant_id BIGINT NOT NULL,
    merchant_amount DECIMAL(10,2) NOT NULL,
    wallet_deducted DECIMAL(10,2) NOT NULL,
    debt_amount DECIMAL(10,2) NOT NULL,
    debt_repaid DECIMAL(10,2) NOT NULL DEFAULT 0,
    platform_amount DECIMAL(10,2) NOT NULL,
    create_time DATETIME NOT NULL,
    UNIQUE KEY uk_after_sales_refund(refund_id),
    KEY idx_after_sales_merchant(merchant_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS after_sales_debt_payments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    settlement_order_id BIGINT NOT NULL,
    refund_id BIGINT NOT NULL,
    merchant_id BIGINT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    create_time DATETIME NOT NULL,
    UNIQUE KEY uk_after_sales_debt_payment(settlement_order_id,refund_id),
    KEY idx_after_sales_debt_merchant(merchant_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 新结算按真实发生时间归属；历史订单没有此事实时由统计回退 complete_time。
CREATE TABLE IF NOT EXISTS order_settlements (
    order_id BIGINT PRIMARY KEY,
    merchant_id BIGINT NOT NULL,
    net_amount DECIMAL(10,2) NOT NULL,
    debt_repaid DECIMAL(10,2) NOT NULL,
    wallet_credited DECIMAL(10,2) NOT NULL,
    settled_at DATETIME NOT NULL,
    KEY idx_order_settlements_merchant_time(merchant_id,settled_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- No FK: independent transactions must never wait on a business row locked by their caller.
CREATE TABLE IF NOT EXISTS external_refund_attempts (
 refund_no VARCHAR(64) PRIMARY KEY, kind VARCHAR(16) NOT NULL,
 order_id BIGINT NOT NULL, payment_id BIGINT NOT NULL, refund_id BIGINT NOT NULL DEFAULT 0,
 channel VARCHAR(16) NOT NULL, out_trade_no VARCHAR(64) NOT NULL,
 provider_transaction_id VARCHAR(128) NOT NULL DEFAULT '',
 amount DECIMAL(10,2) NOT NULL, original_amount DECIMAL(10,2) NOT NULL,
 metadata_json TEXT NOT NULL, status VARCHAR(16) NOT NULL DEFAULT 'REQUESTED',
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY idx_external_refund_recovery(status,updated_at), KEY idx_external_refund_order(order_id,kind,status),
 KEY idx_external_refund_record(refund_id,status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
