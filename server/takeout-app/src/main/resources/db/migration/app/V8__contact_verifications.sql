CREATE TABLE IF NOT EXISTS user_contact_verifications (
    user_id BIGINT NOT NULL,
    kind VARCHAR(8) NOT NULL,
    value_hash VARCHAR(64) NOT NULL,
    verified_at DATETIME NOT NULL,
    PRIMARY KEY(user_id, kind)
);
