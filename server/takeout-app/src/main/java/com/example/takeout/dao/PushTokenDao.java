package com.example.takeout.dao;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public class PushTokenDao {
    private final JdbcTemplate jdbc;

    public PushTokenDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void register(long userId, String tokenHash, String encryptedToken, long updatedAt) {
        jdbc.update("INSERT INTO push_tokens (user_id, token_hash, token_encrypted, updated_at) VALUES (?, ?, ?, ?) "
                        + "ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), "
                        + "token_encrypted = VALUES(token_encrypted), updated_at = VALUES(updated_at)",
                userId, tokenHash, encryptedToken, updatedAt);
    }

    public int unregister(long userId, String tokenHash) {
        return jdbc.update("DELETE FROM push_tokens WHERE user_id = ? AND token_hash = ?", userId, tokenHash);
    }

    public List<String> findEncryptedByUserId(long userId) {
        return jdbc.queryForList("SELECT token_encrypted FROM push_tokens WHERE user_id = ? ORDER BY id",
                String.class, userId);
    }
}
