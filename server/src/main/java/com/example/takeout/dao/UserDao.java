package com.example.takeout.dao;

import com.example.takeout.model.User;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/**
 * 用户数据访问
 */
@Repository
public class UserDao {

    private static final RowMapper<User> MAPPER = (rs, i) -> new User(
            rs.getLong("id"),
            rs.getString("username"),
            rs.getString("avatar"),
            rs.getString("phone"),
            rs.getString("password"),
            rs.getInt("role"),
            rs.getDouble("balance"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public UserDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<User> findByPhone(String phone) {
        return jdbc.query("SELECT * FROM users WHERE phone = ?", MAPPER, phone).stream().findFirst();
    }

    public Optional<User> findById(long id) {
        return jdbc.query("SELECT * FROM users WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public boolean existsByPhone(String phone) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE phone = ?", Integer.class, phone);
        return count != null && count > 0;
    }

    public boolean existsByPhoneExceptUser(String phone, long userId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE phone = ? AND id <> ?",
                Integer.class, phone, userId);
        return count != null && count > 0;
    }

    public User insert(String username, String phone, String passwordHash, int role, double balance, String now) {
        jdbc.update("INSERT INTO users(username, avatar, phone, password, role, balance, create_time) VALUES(?,?,?,?,?,?,?)",
                username, "", phone, passwordHash, role, balance, now);
        long id = jdbc.queryForObject("SELECT id FROM users WHERE phone = ?", Long.class, phone);
        return new User(id, username, "", phone, passwordHash, role, balance, now);
    }

    public void updateBalance(long userId, double balance) {
        jdbc.update("UPDATE users SET balance = ? WHERE id = ?", balance, userId);
    }

    public void updateProfile(long userId, String username, String phone) {
        jdbc.update("UPDATE users SET username = ?, phone = ? WHERE id = ?", username, phone, userId);
    }
}
