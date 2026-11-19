CREATE TABLE IF NOT EXISTS account_lifecycle_guards (
    user_id BIGINT PRIMARY KEY,
    closed_at DATETIME NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
