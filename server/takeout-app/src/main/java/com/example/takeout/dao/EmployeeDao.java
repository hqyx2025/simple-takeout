package com.example.takeout.dao;

import com.example.takeout.model.Employee;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;
import com.example.takeout.service.PersonalDataCrypto;

import java.util.List;

/** 门店员工数据访问。 */
@Repository
public class EmployeeDao {

    private final RowMapper<Employee> MAPPER = (rs, i) -> new Employee(
            rs.getLong("id"),
            rs.getLong("store_id"),
            rs.getLong("user_id"),
            rs.getString("username"),
            readPhone(rs),
            rs.getString("role_name"),
            rs.getInt("status"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;
    private final PersonalDataCrypto crypto;

    public EmployeeDao(JdbcTemplate jdbc) {
        this(jdbc, null);
    }

    @org.springframework.beans.factory.annotation.Autowired
    public EmployeeDao(JdbcTemplate jdbc, PersonalDataCrypto crypto) {
        this.jdbc = jdbc; this.crypto = crypto;
    }

    private String readPhone(java.sql.ResultSet row) throws java.sql.SQLException {
        String cipher = crypto == null ? null : row.getString("phone_encrypted");
        return cipher == null ? row.getString("phone") : crypto.decrypt(cipher, "users.phone");
    }

    /** 用户是否为该店铺的启用员工（按店鉴权依据）。 */
    public boolean isEmployee(long userId, long storeId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM employees WHERE user_id = ? AND store_id = ? AND status = 1",
                Integer.class, userId, storeId);
        return count != null && count > 0;
    }

    public List<Employee> listByStore(long storeId) {
        return jdbc.query("SELECT e.id, e.store_id, e.user_id, u.username, u.phone, " + (crypto == null ? "" : "u.phone_encrypted, ") + "e.role_name, e.status, e.create_time " +
                        "FROM employees e JOIN users u ON u.id = e.user_id WHERE e.store_id = ? ORDER BY e.id DESC",
                MAPPER, storeId);
    }

    public long insert(long storeId, long userId, String roleName, String now) {
        jdbc.update("INSERT INTO employees(store_id, user_id, role_name, status, create_time) VALUES(?,?,?,1,?)",
                storeId, userId, roleName, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public boolean delete(long storeId, long id) {
        return jdbc.update("DELETE FROM employees WHERE id = ? AND store_id = ?", id, storeId) == 1;
    }
}
