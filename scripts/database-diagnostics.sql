-- Read-only operational probes. Run against the intended schema through its private connection.
-- Plans depend on actual rows/statistics: these probes do not claim capacity or prescribe new indexes.
SELECT VERSION() AS database_version, @@transaction_isolation AS isolation_level,
       @@max_connections AS max_connections, @@innodb_buffer_pool_size AS buffer_pool_bytes;
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';
SHOW INDEX FROM orders;
SHOW INDEX FROM users;
SHOW INDEX FROM user_phone_search;

-- Same predicate shape as the encrypted phone lookup, using non-sensitive example values.
EXPLAIN FORMAT=JSON SELECT * FROM users
WHERE phone_lookup='diagnostic-nonmatching-index-token'
   OR (phone_encrypted IS NULL AND phone='13800000000');

-- The existing rider-pool index prefilters status/rider/readiness; the real pool also joins stores,
-- checks range/fulfillment and sorts compatible timestamps. Inspect that complete query before tuning.
EXPLAIN FORMAT=JSON SELECT id, store_id, ready_time FROM orders
WHERE status=2 AND rider_id=0 AND ready_time<>'' AND delivery_type='DELIVERY' LIMIT 30;

-- Normalized digests omit SQL literal values; do not enable or publish raw slow logs containing PII.
SELECT DIGEST_TEXT, COUNT_STAR, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_seconds,
       ROUND(AVG_TIMER_WAIT/1000000000,3) AS average_ms, SUM_ROWS_EXAMINED, SUM_ROWS_SENT
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME=DATABASE()
ORDER BY SUM_TIMER_WAIT DESC LIMIT 20;
