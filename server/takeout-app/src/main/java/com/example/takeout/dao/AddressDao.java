package com.example.takeout.dao;

import com.example.takeout.model.Address;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * 收货地址数据访问
 */
@Repository
public class AddressDao {

    private static final RowMapper<Address> MAPPER = (rs, i) -> new Address(
            rs.getLong("id"),
            rs.getLong("user_id"),
            rs.getString("name"),
            rs.getString("phone"),
            rs.getString("detail"),
            rs.getInt("is_default"),
            rs.getString("create_time"),
            rs.getObject("latitude", Double.class),
            rs.getObject("longitude", Double.class)
    );

    private final JdbcTemplate jdbc;

    public AddressDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Address> listByUser(long userId) {
        return jdbc.query("SELECT * FROM addresses WHERE user_id = ? ORDER BY is_default DESC, id DESC", MAPPER, userId);
    }

    public long insert(long userId, String name, String phone, String detail, int isDefault,
                       Double latitude, Double longitude, String now) {
        if (isDefault == 1) {
            clearDefault(userId);
        }
        jdbc.update("INSERT INTO addresses(user_id, name, phone, detail, is_default, latitude, longitude, create_time) VALUES(?,?,?,?,?,?,?,?)",
                userId, name, phone, detail, isDefault, latitude, longitude, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void delete(long userId, long id) {
        jdbc.update("DELETE FROM addresses WHERE id = ? AND user_id = ?", id, userId);
    }

    public void update(long userId, long id, String name, String phone, String detail, int isDefault,
                       Double latitude, Double longitude) {
        if (isDefault == 1) {
            clearDefault(userId);
        }
        jdbc.update("UPDATE addresses SET name = ?, phone = ?, detail = ?, is_default = ?, latitude = ?, longitude = ? WHERE id = ? AND user_id = ?",
                name, phone, detail, isDefault, latitude, longitude, id, userId);
    }

    public void setDefault(long userId, long id) {
        clearDefault(userId);
        jdbc.update("UPDATE addresses SET is_default = 1 WHERE id = ? AND user_id = ?", id, userId);
    }

    private void clearDefault(long userId) {
        jdbc.update("UPDATE addresses SET is_default = 0 WHERE user_id = ?", userId);
    }
}
