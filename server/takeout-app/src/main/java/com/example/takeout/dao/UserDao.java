package com.example.takeout.dao;

import com.example.takeout.model.User;
import com.example.takeout.common.CrudPermissions;
import com.example.takeout.model.AdminEmployee;
import com.example.takeout.model.AdminUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;
import com.example.takeout.service.PersonalDataCrypto;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;
import java.util.List;

/**
 * 用户数据访问
 */
@Repository
public class UserDao {

    private final RowMapper<User> MAPPER = (rs, i) -> new User(
            rs.getLong("id"),
            rs.getString("username"),
            rs.getString("avatar"),
            readPhone(rs),
            rs.getString("password"),
            rs.getInt("role"),
            rs.getInt("status"),
            rs.getDouble("balance"),
            rs.getString("create_time"),
            rs.getString("password_changed_at"),
            rs.getString("payment_password_hash"),
            rs.getString("email"),
            rs.getInt("can_create") == 1,
            rs.getInt("can_read") == 1,
            rs.getInt("can_update") == 1,
            rs.getInt("can_delete") == 1
    );

    private final JdbcTemplate jdbc;
    private final PersonalDataCrypto crypto;
    private final PersonalPhoneIndex phoneIndex;

    public UserDao(JdbcTemplate jdbc) {
        this(jdbc, null);
    }

    @org.springframework.beans.factory.annotation.Autowired
    public UserDao(JdbcTemplate jdbc, PersonalDataCrypto crypto) {
        this.jdbc = jdbc; this.crypto = crypto;
        this.phoneIndex = crypto == null ? null : new PersonalPhoneIndex(jdbc, crypto);
    }

    private String readPhone(java.sql.ResultSet row) throws java.sql.SQLException {
        String encrypted = crypto == null ? null : row.getString("phone_encrypted");
        return encrypted == null ? row.getString("phone") : crypto.decrypt(encrypted, "users.phone");
    }

    public Optional<User> findByPhone(String phone) {
        if (crypto != null) return jdbc.query("SELECT * FROM users WHERE phone_lookup=? OR (phone_encrypted IS NULL AND phone=?)",
                MAPPER, crypto.hash("phone:exact", phone), phone).stream().findFirst();
        return jdbc.query("SELECT * FROM users WHERE phone = ?", MAPPER, phone).stream().findFirst();
    }

    public Optional<User> findByPhoneForUpdate(String phone) {
        if (crypto != null) return jdbc.query("SELECT * FROM users WHERE phone_lookup=? OR (phone_encrypted IS NULL AND phone=?) FOR UPDATE",
                MAPPER, crypto.hash("phone:exact", phone), phone).stream().findFirst();
        return jdbc.query("SELECT * FROM users WHERE phone = ? FOR UPDATE", MAPPER, phone).stream().findFirst();
    }

    public Optional<User> findById(long id) {
        return jdbc.query("SELECT * FROM users WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public Optional<User> findByIdForUpdate(long id) {
        return jdbc.query("SELECT * FROM users WHERE id = ? FOR UPDATE", MAPPER, id).stream().findFirst();
    }

    public boolean existsByPhone(String phone) {
        if (crypto != null) return findByPhone(phone).isPresent();
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE phone = ?", Integer.class, phone);
        return count != null && count > 0;
    }

    public boolean existsByPhoneExceptUser(String phone, long userId) {
        if (crypto != null) return findByPhone(phone).filter(user -> user.id() != userId).isPresent();
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE phone = ? AND id <> ?",
                Integer.class, phone, userId);
        return count != null && count > 0;
    }

    public boolean existsByUsername(String username) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE username = ?", Integer.class, username);
        return count != null && count > 0;
    }

    public boolean existsByUsernameExceptUser(String username, long userId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE username = ? AND id <> ?",
                Integer.class, username, userId);
        return count != null && count > 0;
    }

    public List<AdminEmployee> listEmployees() {
        return jdbc.query("SELECT u.id, u.username, u.phone, " + encryptedPhoneSelection() + "u.role, u.status, u.create_time, " +
                        "COUNT(s.id) AS store_count FROM users u LEFT JOIN stores s ON s.owner_id = u.id " +
                        "WHERE u.role = 1 GROUP BY u.id, u.username, u.phone, u.role, u.status, u.create_time " +
                        "ORDER BY u.id DESC",
                (rs, i) -> new AdminEmployee(rs.getLong("id"), rs.getString("username"),
                        readPhone(rs), rs.getInt("role"), rs.getInt("status"),
                        rs.getInt("store_count"), rs.getString("create_time")));
    }

    public List<AdminUser> listForAdmin(Integer role, Integer status, String keyword) {
        StringBuilder sql = new StringBuilder("SELECT u.id, u.username, u.phone, " + encryptedPhoneSelection() + "u.role, u.status, " +
                "u.balance, u.create_time, COUNT(s.id) AS store_count FROM users u " +
                "LEFT JOIN stores s ON s.owner_id = u.id WHERE ");
        List<Object> args = new java.util.ArrayList<>();
        appendAdminUserFilters(sql, args, role, status, keyword);
        sql.append(" GROUP BY u.id, u.username, u.phone, u.role, u.status, u.balance, u.create_time ORDER BY u.id DESC");
        return queryAdminUsers(sql.toString(), args);
    }

    public int countForAdmin(Integer role, Integer status, String keyword) {
        StringBuilder sql = new StringBuilder("SELECT COUNT(*) FROM users u WHERE ");
        List<Object> args = new java.util.ArrayList<>();
        appendAdminUserFilters(sql, args, role, status, keyword);
        Integer count = jdbc.queryForObject(sql.toString(), Integer.class, args.toArray());
        return count == null ? 0 : count;
    }

    public List<AdminUser> listForAdmin(Integer role, Integer status, String keyword, int pageSize, long offset) {
        StringBuilder sql = new StringBuilder("SELECT u.id, u.username, u.phone, " + encryptedPhoneSelection() + "u.role, u.status, " +
                "u.balance, u.create_time, COUNT(s.id) AS store_count FROM users u " +
                "LEFT JOIN stores s ON s.owner_id = u.id WHERE ");
        List<Object> args = new java.util.ArrayList<>();
        appendAdminUserFilters(sql, args, role, status, keyword);
        sql.append(" GROUP BY u.id, u.username, u.phone, u.role, u.status, u.balance, u.create_time " +
                "ORDER BY u.id DESC LIMIT ? OFFSET ?");
        args.add(pageSize);
        args.add(offset);
        return queryAdminUsers(sql.toString(), args);
    }

    private void appendAdminUserFilters(StringBuilder sql, List<Object> args,
                                        Integer role, Integer status, String keyword) {
        sql.append("u.role <> 2");
        if (role != null) {
            sql.append(" AND u.role = ?");
            args.add(role);
        }
        if (status != null) {
            sql.append(" AND u.status = ?");
            args.add(status);
        }
        if (keyword != null && !keyword.isBlank()) {
            if (crypto != null) {
                sql.append(" AND (u.username LIKE ? OR "); args.add("%" + keyword.trim() + "%");
                sql.append(phoneIndex.like(keyword, args)).append(')');
                return;
            }
            sql.append(" AND (u.username LIKE ? OR u.phone LIKE ?)");
            String value = "%" + keyword.trim() + "%";
            args.add(value);
            args.add(value);
        }
    }

    private List<AdminUser> queryAdminUsers(String sql, List<Object> args) {
        return jdbc.query(sql, (rs, i) -> new AdminUser(
                rs.getLong("id"), rs.getString("username"), readPhone(rs),
                rs.getInt("role"), rs.getInt("status"), rs.getDouble("balance"),
                rs.getInt("store_count"), rs.getString("create_time")
        ), args.toArray());
    }

    public void updateStatus(long id, int status) {
        jdbc.update("UPDATE users SET status = ? WHERE id = ? AND role <> 2", status, id);
    }

    public void updateCrudPermissions(long id, CrudPermissions permissions) {
        jdbc.update("UPDATE users SET can_create=?,can_read=?,can_update=?,can_delete=? WHERE id=? AND role<>2",
                permissions.canCreate(), permissions.canRead(), permissions.canUpdate(), permissions.canDelete(), id);
    }

    @Transactional
    public AdminEmployee insertEmployee(String username, String phone, String passwordHash, String now) {
        if (crypto != null) {
            User user = insert(username, phone, passwordHash, 1, 0, now);
            return listEmployees().stream().filter(employee -> employee.id() == user.id()).findFirst().orElseThrow();
        }
        jdbc.update("INSERT INTO users(username, avatar, phone, password, role, status, balance, create_time) " +
                        "VALUES(?,?,?,?,1,1,0,?)", username, "", phone, passwordHash, now);
        long id = jdbc.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, username);
        return listEmployees().stream().filter(employee -> employee.id() == id).findFirst()
                .orElseThrow(() -> new IllegalStateException("员工创建后查询失败"));
    }

    @Transactional
    public void updateEmployee(long id, String username, String phone) {
        if (crypto != null) {
            if (jdbc.update("UPDATE users SET username=?,phone=?,phone_encrypted=?,phone_lookup=?,phone_length=? WHERE id=? AND role=1",
                    username, crypto.phoneToken(phone), crypto.encrypt(phone, "users.phone"), crypto.hash("phone:exact", phone),
                    phone.codePointCount(0, phone.length()), id) == 1) phoneIndex.replace(id, phone);
            return;
        }
        jdbc.update("UPDATE users SET username = ?, phone = ? WHERE id = ? AND role = 1", username, phone, id);
    }

    public void updateEmployeeStatus(long id, int status) {
        jdbc.update("UPDATE users SET status = ? WHERE id = ? AND role = 1", status, id);
    }

    @Transactional
    public User insert(String username, String phone, String passwordHash, int role, double balance, String now) {
        if (crypto != null) return insert(username, phone, null, passwordHash, role, balance, now);
        jdbc.update("INSERT INTO users(username, avatar, phone, password, role, balance, create_time) VALUES(?,?,?,?,?,?,?)",
                username, "", phone, passwordHash, role, balance, now);
        long id = jdbc.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, username);
        return new User(id, username, "", phone, passwordHash, role, balance, now);
    }

    @Transactional
    public User insert(String username, String phone, String email, String passwordHash,
                       int role, double balance, String now) {
        if (crypto != null) {
            jdbc.update("INSERT INTO users(username,avatar,phone,email,password,role,balance,create_time,phone_encrypted,phone_lookup,phone_length) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                    username, "", crypto.phoneToken(phone), email, passwordHash, role, balance, now,
                    crypto.encrypt(phone, "users.phone"), crypto.hash("phone:exact", phone), phone.codePointCount(0, phone.length()));
            long id = jdbc.queryForObject("SELECT id FROM users WHERE username=?", Long.class, username);
            // New users have no old terms. Deleting an empty range here would gap-lock concurrent inserts.
            phoneIndex.insert(id, phone);
            return new User(id, username, "", phone, passwordHash, role, 1, balance, now, "", "", email);
        }
        jdbc.update("INSERT INTO users(username, avatar, phone, email, password, role, balance, create_time) " +
                        "VALUES(?,?,?,?,?,?,?,?)", username, "", phone, email, passwordHash, role, balance, now);
        long id = jdbc.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, username);
        return new User(id, username, "", phone, passwordHash, role, 1, balance, now, "", "", email);
    }

    /**
     * 原子加款（退款/结算入账）：库内自增，避免「读余额→加→整值写回」在并发下丢更新。
     */
    public void addBalance(long userId, double amount) {
        jdbc.update("UPDATE users SET balance = ROUND(balance + ?, 2) WHERE id = ?", amount, userId);
    }

    /**
     * 原子扣款（支付扣余额）：条件更新，余额不足或并发扣款返回 false。
     * 注意不要改回「读余额→减→setBalance」：同一用户两笔订单并发支付会各读到同一份旧余额，
     * 后写入者覆盖前者，等于少扣一笔（实测可白吃一单）。
     */
    public boolean deductBalance(long userId, double amount) {
        return jdbc.update("UPDATE users SET balance = ROUND(balance - ?, 2) WHERE id = ? AND balance >= ?",
                amount, userId, amount) == 1;
    }

    @Transactional
    public void updateProfile(long userId, String username, String phone) {
        if (crypto != null) {
            updateProfile(userId, username, phone, findById(userId).map(User::email).orElse(null)); return;
        }
        jdbc.update("UPDATE users SET username = ?, phone = ? WHERE id = ?", username, phone, userId);
    }

    @Transactional
    public void updateProfile(long userId, String username, String phone, String email) {
        if (crypto != null) {
            if (jdbc.update("UPDATE users SET username=?,phone=?,email=?,phone_encrypted=?,phone_lookup=?,phone_length=? WHERE id=?",
                    username, crypto.phoneToken(phone), email, crypto.encrypt(phone, "users.phone"),
                    crypto.hash("phone:exact", phone), phone.codePointCount(0, phone.length()), userId) == 1) phoneIndex.replace(userId, phone);
            return;
        }
        jdbc.update("UPDATE users SET username = ?, phone = ?, email = ? WHERE id = ?",
                username, phone, email, userId);
    }

    /**
     * 改密：同时写入 password_changed_at，使签发时间早于改密时刻的 token 全部失效。
     */
    public void updatePassword(long userId, String passwordHash, String changedAt) {
        jdbc.update("UPDATE users SET password = ?, password_changed_at = ? WHERE id = ?",
                passwordHash, changedAt, userId);
        jdbc.update("UPDATE token_blacklist SET reason = 'rx:password' " +
                        "WHERE user_id = ? AND LEFT(reason, 3) IN ('rf:', 'ru:')",
                userId);
    }

    /** Rehash without revoking existing sessions; only update if the verified hash is still current. */
    public void upgradePasswordHash(long userId, String currentHash, String upgradedHash) {
        jdbc.update("UPDATE users SET password = ? WHERE id = ? AND password = ?",
                upgradedHash, userId, currentHash);
    }

    public void updatePaymentPassword(long userId, String passwordHash) {
        jdbc.update("UPDATE users SET payment_password_hash = ? WHERE id = ?",
                passwordHash, userId);
    }

    private String encryptedPhoneSelection() { return crypto == null ? "" : "u.phone_encrypted, "; }

    @Transactional
    public void reencryptPhone(long id) {
        var row = jdbc.queryForMap("SELECT phone_encrypted,phone_lookup FROM users WHERE id=? FOR UPDATE", id);
        if (crypto.isCurrent((String) row.get("phone_encrypted")) && row.get("phone_lookup") != null) return;
        User user = findById(id).orElseThrow();
        jdbc.update("UPDATE users SET phone=?,phone_encrypted=?,phone_lookup=?,phone_length=? WHERE id=?",
                crypto.phoneToken(user.phone()), crypto.encrypt(user.phone(), "users.phone"), crypto.hash("phone:exact", user.phone()),
                user.phone().codePointCount(0, user.phone().length()), id);
        if (row.get("phone_encrypted") == null) phoneIndex.insert(id, user.phone());
        else phoneIndex.replace(id, user.phone());
    }
}
