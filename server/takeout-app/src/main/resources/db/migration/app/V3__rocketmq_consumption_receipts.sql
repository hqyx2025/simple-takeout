-- Receipts outlive Outbox cleanup and broker replay. Do not expire them using a Redis TTL.
CREATE TABLE IF NOT EXISTS mq_consumptions (
    consumer_group VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    event_id BIGINT NOT NULL,
    consumed_at DATETIME NULL,
    PRIMARY KEY (consumer_group,event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
