-- Additive storage; keep existing columns/constraints for API and old-data compatibility.
ALTER TABLE users ADD COLUMN phone_encrypted TEXT NULL,
    ADD COLUMN phone_lookup VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN phone_length SMALLINT NOT NULL DEFAULT 0,
    ADD UNIQUE KEY uk_users_phone_lookup(phone_lookup);
CREATE TABLE user_phone_search (
    user_id BIGINT NOT NULL, start_pos SMALLINT NOT NULL, span SMALLINT NOT NULL,
    token VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    PRIMARY KEY(user_id,start_pos,span), KEY idx_phone_search_token(token,user_id),
    CONSTRAINT fk_phone_search_user FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
ALTER TABLE addresses ADD COLUMN private_data_encrypted TEXT NULL;
ALTER TABLE riders ADD COLUMN private_data_encrypted TEXT NULL;
ALTER TABLE orders MODIFY address MEDIUMTEXT NOT NULL;
CREATE TABLE personal_data_key_state (
    id TINYINT PRIMARY KEY, index_check VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
