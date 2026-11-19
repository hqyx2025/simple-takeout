CREATE TABLE IF NOT EXISTS wallet_movements (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    balance_before DECIMAL(10,2) NOT NULL,
    balance_after DECIMAL(10,2) NOT NULL,
    delta DECIMAL(10,2) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    KEY idx_wallet_movements_user(user_id, id)
);
-- Observed movements only: no invented opening balances or historical backfill.
CREATE TRIGGER IF NOT EXISTS takeout_wallet_movement
AFTER UPDATE ON users FOR EACH ROW
INSERT INTO wallet_movements(user_id,balance_before,balance_after,delta)
SELECT NEW.id,OLD.balance,NEW.balance,NEW.balance-OLD.balance WHERE NEW.balance<>OLD.balance;

CREATE TABLE IF NOT EXISTS financial_reconciliation_issues (
    check_type VARCHAR(32) NOT NULL,
    entity_id BIGINT NOT NULL,
    evidence TEXT NOT NULL,
    first_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at DATETIME NULL,
    PRIMARY KEY(check_type,entity_id),
    KEY idx_reconciliation_open(resolved_at,last_seen)
);
CREATE TABLE IF NOT EXISTS financial_reconciliation_progress (
    task VARCHAR(16) PRIMARY KEY,
    scan_date DATE NOT NULL,
    last_id BIGINT NOT NULL DEFAULT 0,
    complete TINYINT NOT NULL DEFAULT 0
);
