package com.example.takeout.dao;

import com.example.takeout.model.Address;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Repository;

import java.sql.Statement;
import java.util.List;
import java.util.Optional;

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
            rs.getObject("longitude", Double.class),
            rs.getString("map_address"),
            rs.getString("door_detail"),
            rs.getString("tag")
    );

    private final JdbcTemplate jdbc;

    public AddressDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Address> listByUser(long userId) {
        return jdbc.query("SELECT * FROM addresses WHERE user_id = ? ORDER BY is_default DESC, id DESC", MAPPER, userId);
    }

    public int countByUser(long userId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM addresses WHERE user_id = ?", Integer.class, userId);
        return count == null ? 0 : count;
    }

    public Optional<Address> findByIdAndUser(long id, long userId) {
        return jdbc.query("SELECT * FROM addresses WHERE id = ? AND user_id = ?", MAPPER, id, userId)
                .stream().findFirst();
    }

    public long insert(long userId, String name, String phone, String detail, int isDefault,
                       Double latitude, Double longitude, String mapAddress, String doorDetail,
                       String tag, String now) {
        if (isDefault == 1) {
            clearDefault(userId);
        }
        var keyHolder = new GeneratedKeyHolder();
        jdbc.update(connection -> {
            var statement = connection.prepareStatement(
                    "INSERT INTO addresses(user_id, name, phone, detail, is_default, latitude, longitude, map_address, door_detail, tag, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                    Statement.RETURN_GENERATED_KEYS);
            statement.setLong(1, userId);
            statement.setString(2, name);
            statement.setString(3, phone);
            statement.setString(4, detail);
            statement.setInt(5, isDefault);
            statement.setObject(6, latitude);
            statement.setObject(7, longitude);
            statement.setString(8, mapAddress);
            statement.setString(9, doorDetail);
            statement.setString(10, tag);
            statement.setString(11, now);
            return statement;
        }, keyHolder);
        Number key = keyHolder.getKey();
        if (key == null) {
            throw new IllegalStateException("地址写入成功但未返回主键");
        }
        return key.longValue();
    }

    public boolean delete(long userId, long id) {
        return jdbc.update("DELETE FROM addresses WHERE id = ? AND user_id = ?", id, userId) == 1;
    }

    public boolean update(long userId, long id, String name, String phone, String detail, int isDefault,
                          Double latitude, Double longitude, String mapAddress, String doorDetail, String tag) {
        if (isDefault == 1) {
            clearDefault(userId);
        }
        return jdbc.update("UPDATE addresses SET name = ?, phone = ?, detail = ?, is_default = ?, latitude = ?, longitude = ?, map_address = ?, door_detail = ?, tag = ? WHERE id = ? AND user_id = ?",
                name, phone, detail, isDefault, latitude, longitude, mapAddress, doorDetail, tag, id, userId) == 1;
    }

    public boolean setDefault(long userId, long id) {
        if (findByIdAndUser(id, userId).isEmpty()) {
            return false;
        }
        clearDefault(userId);
        return jdbc.update("UPDATE addresses SET is_default = 1 WHERE id = ? AND user_id = ?", id, userId) == 1;
    }

    private void clearDefault(long userId) {
        jdbc.update("UPDATE addresses SET is_default = 0 WHERE user_id = ?", userId);
    }
}
