SET @takeout_boundary_ddl = IF(
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=DATABASE()
           AND table_name='order_create_requests' AND column_name='request_hash'),
    'SELECT 1', 'ALTER TABLE order_create_requests ADD COLUMN request_hash CHAR(64) DEFAULT NULL');
PREPARE takeout_boundary_stmt FROM @takeout_boundary_ddl;
EXECUTE takeout_boundary_stmt;
DEALLOCATE PREPARE takeout_boundary_stmt;

SET @takeout_boundary_ddl = IF(
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=DATABASE()
           AND table_name='external_refund_attempts' AND column_name='failure_count'),
    'SELECT 1', 'ALTER TABLE external_refund_attempts ADD COLUMN failure_count INT NOT NULL DEFAULT 0, ADD COLUMN next_attempt_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP');
PREPARE takeout_boundary_stmt FROM @takeout_boundary_ddl;
EXECUTE takeout_boundary_stmt;
DEALLOCATE PREPARE takeout_boundary_stmt;

CREATE TABLE IF NOT EXISTS order_background_retries (
    order_id BIGINT NOT NULL,
    task VARCHAR(16) NOT NULL,
    failure_count INT NOT NULL DEFAULT 0,
    next_attempt_at DATETIME NOT NULL,
    PRIMARY KEY(order_id, task),
    KEY idx_order_background_due(task, next_attempt_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET @takeout_boundary_ddl = IF(
    EXISTS(SELECT 1 FROM information_schema.statistics WHERE table_schema=DATABASE()
           AND table_name='external_refund_attempts' AND index_name='idx_external_refund_due'),
    'SELECT 1', 'ALTER TABLE external_refund_attempts ADD INDEX idx_external_refund_due(status,next_attempt_at,refund_no)');
PREPARE takeout_boundary_stmt FROM @takeout_boundary_ddl;
EXECUTE takeout_boundary_stmt;
DEALLOCATE PREPARE takeout_boundary_stmt;
