CREATE TABLE mq_consumer_failures (
    consumer_group VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    event_key VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    first_failed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_failed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    attempts INT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (consumer_group,event_key),
    KEY idx_mq_failure_age(consumer_group,first_failed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE mq_replay_locks (
    consumer_group VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
