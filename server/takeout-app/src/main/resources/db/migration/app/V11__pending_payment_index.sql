SET @takeout_pending_payment_ddl = IF(
    EXISTS(SELECT 1 FROM information_schema.statistics
           WHERE table_schema = DATABASE() AND table_name = 'payment_transactions'
             AND index_name = 'idx_payment_transactions_pending'),
    'SELECT 1', 'CREATE INDEX idx_payment_transactions_pending ON payment_transactions(status,id)');
PREPARE takeout_pending_payment_stmt FROM @takeout_pending_payment_ddl;
EXECUTE takeout_pending_payment_stmt;
DEALLOCATE PREPARE takeout_pending_payment_stmt;
