-- Verify the bootstrap/legacy upgrades before recording their versioned baseline.
-- Future additive schema changes belong in V2+, without editing this checksum.
SELECT id, owner, lease_until FROM outbox_events WHERE 1 = 0;
SELECT user_id, request_key, order_id FROM order_create_requests WHERE 1 = 0;
SELECT cancel_source, cancel_reason_code, reject_spec_id FROM orders WHERE 1 = 0;
