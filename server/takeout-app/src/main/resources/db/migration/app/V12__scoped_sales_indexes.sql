SET @takeout_sales_ddl = IF(
    EXISTS(SELECT 1 FROM information_schema.statistics WHERE table_schema=DATABASE()
           AND table_name='orders' AND index_name='idx_orders_store_sales'),
    'SELECT 1', 'CREATE INDEX idx_orders_store_sales ON orders(store_id,status,escrow_status,pay_time_dt,pay_time)');
PREPARE takeout_sales_stmt FROM @takeout_sales_ddl;
EXECUTE takeout_sales_stmt;
DEALLOCATE PREPARE takeout_sales_stmt;

SET @takeout_sales_ddl = IF(
    EXISTS(SELECT 1 FROM information_schema.statistics WHERE table_schema=DATABASE()
           AND table_name='order_items' AND index_name='idx_order_items_sales'),
    'SELECT 1', 'CREATE INDEX idx_order_items_sales ON order_items(order_id,goods_id,quantity)');
PREPARE takeout_sales_stmt FROM @takeout_sales_ddl;
EXECUTE takeout_sales_stmt;
DEALLOCATE PREPARE takeout_sales_stmt;
