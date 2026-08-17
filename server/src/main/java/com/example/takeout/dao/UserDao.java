package com.example.takeout.dao;

import com.example.takeout.model.User;
import com.example.takeout.model.AdminEmployee;
import com.example.takeout.model.AdminUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.List;

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

    public boolean isDisabled(long userId) {
        Integer status = jdbc.queryForObject("SELECT status FROM users WHERE id = ?", Integer.class, userId);
        return status != null && status == 0;
    }

    public List<AdminEmployee> listEmployees() {
        return jdbc.query("SELECT u.id, u.username, u.phone, u.role, u.status, u.create_time, " +
                        "COUNT(s.id) AS store_count FROM users u LEFT JOIN stores s ON s.owner_id = u.id " +
                        "WHERE u.role = 1 GROUP BY u.id, u.username, u.phone, u.role, u.status, u.create_time " +
                        "ORDER BY u.id DESC",
                (rs, i) -> new AdminEmployee(rs.getLong("id"), rs.getString("username"),
                        rs.getString("phone"), rs.getInt("role"), rs.getInt("status"),
                        rs.getInt("store_count"), rs.getString("create_time")));
    }

    public List<AdminUser> listForAdmin(Integer role, Integer status, String keyword) {
        StringBuilder sql = new StringBuilder("SELECT u.id, u.username, u.phone, u.role, u.status, " +
                "u.balance, u.create_time, COUNT(s.id) AS store_count FROM users u " +
                "LEFT JOIN stores s ON s.owner_id = u.id WHERE u.role <> 2");
        List<Object> args = new java.util.ArrayList<>();
        if (role != null) {
            sql.append(" AND u.role = ?");
            args.add(role);
        }
        if (status != null) {
            sql.append(" AND u.status = ?");
            args.add(status);
        }
        if (keyword != null && !keyword.isBlank()) {
            sql.append(" AND (u.username LIKE ? OR u.phone LIKE ?)");
            String value = "%" + keyword.trim() + "%";
            args.add(value);
            args.add(value);
        }
        sql.append(" GROUP BY u.id, u.username, u.phone, u.role, u.status, u.balance, u.create_time ORDER BY u.id DESC");
        return jdbc.query(sql.toString(), (rs, i) -> new AdminUser(
                rs.getLong("id"), rs.getString("username"), rs.getString("phone"),
                rs.getInt("role"), rs.getInt("status"), rs.getDouble("balance"),
                rs.getInt("store_count"), rs.getString("create_time")
        ), args.toArray());
    }

    public void updateStatus(long id, int status) {
        jdbc.update("UPDATE users SET status = ? WHERE id = ? AND role <> 2", status, id);
    }

    public AdminEmployee insertEmployee(String username, String phone, String passwordHash, String now) {
        jdbc.update("INSERT INTO users(username, avatar, phone, password, role, status, balance, create_time) " +
                        "VALUES(?,?,?,?,1,1,0,?)", username, "", phone, passwordHash, now);
        long id = jdbc.queryForObject("SELECT id FROM users WHERE phone = ?", Long.class, phone);
        return listEmployees().stream().filter(employee -> employee.id() == id).findFirst()
                .orElseThrow(() -> new IllegalStateException("员工创建后查询失败"));
    }

    public void updateEmployee(long id, String username, String phone) {
        jdbc.update("UPDATE users SET username = ?, phone = ? WHERE id = ? AND role = 1", username, phone, id);
    }

    public void updateEmployeeStatus(long id, int status) {
        jdbc.update("UPDATE users SET status = ? WHERE id = ? AND role = 1", status, id);
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
