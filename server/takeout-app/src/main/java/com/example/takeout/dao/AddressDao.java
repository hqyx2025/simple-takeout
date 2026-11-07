package com.example.takeout.dao;

import com.example.takeout.model.Address;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Repository;
import com.example.takeout.service.PersonalDataCrypto;

import java.sql.Statement;
import java.util.List;
import java.util.Optional;

/**
 * 收货地址数据访问
 */
@Repository
public class AddressDao {

    private final RowMapper<Address> MAPPER = (rs, i) -> {
        PrivateAddress data = readPrivate(rs);
        return new Address(rs.getLong("id"), rs.getLong("user_id"), data.name(), data.phone(), data.detail(),
                rs.getInt("is_default"), rs.getString("create_time"), data.latitude(), data.longitude(),
                data.mapAddress(), data.doorDetail(), rs.getString("tag"));
    };

    public record PrivateAddress(String name, String phone, String detail, Double latitude, Double longitude,
                                 String mapAddress, String doorDetail) {
        @Override public String toString() { return "PrivateAddress[redacted]"; }
    }

    private final JdbcTemplate jdbc;
    private final PersonalDataCrypto crypto;

    public AddressDao(JdbcTemplate jdbc) {
        this(jdbc, null);
    }

    @org.springframework.beans.factory.annotation.Autowired
    public AddressDao(JdbcTemplate jdbc, PersonalDataCrypto crypto) {
        this.jdbc = jdbc; this.crypto = crypto;
    }

    private PrivateAddress readPrivate(java.sql.ResultSet row) throws java.sql.SQLException {
        String encrypted = crypto == null ? null : row.getString("private_data_encrypted");
        if (encrypted != null) return crypto.decryptJson(encrypted, "addresses.private", PrivateAddress.class);
        return new PrivateAddress(row.getString("name"), row.getString("phone"), row.getString("detail"),
                row.getObject("latitude", Double.class), row.getObject("longitude", Double.class),
                row.getString("map_address"), row.getString("door_detail"));
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
        String encrypted = crypto == null ? null : crypto.encryptJson(new PrivateAddress(name, phone, detail, latitude, longitude, mapAddress, doorDetail), "addresses.private");
        jdbc.update(connection -> {
            var statement = connection.prepareStatement(
                    "INSERT INTO addresses(user_id, name, phone, detail, is_default, latitude, longitude, map_address, door_detail, tag, create_time" +
                            (crypto == null ? ") VALUES(?,?,?,?,?,?,?,?,?,?,?)" : ",private_data_encrypted) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)"),
                    Statement.RETURN_GENERATED_KEYS);
            statement.setLong(1, userId);
            statement.setString(2, crypto == null ? name : "");
            statement.setString(3, crypto == null ? phone : "");
            statement.setString(4, crypto == null ? detail : "");
            statement.setInt(5, isDefault);
            statement.setObject(6, crypto == null ? latitude : null);
            statement.setObject(7, crypto == null ? longitude : null);
            statement.setString(8, crypto == null ? mapAddress : "");
            statement.setString(9, crypto == null ? doorDetail : "");
            statement.setString(10, tag);
            statement.setString(11, now);
            if (crypto != null) statement.setString(12, encrypted);
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
        if (crypto != null) return jdbc.update("UPDATE addresses SET name='',phone='',detail='',latitude=NULL,longitude=NULL,map_address='',door_detail='',private_data_encrypted=?,is_default=?,tag=? WHERE id=? AND user_id=?",
                crypto.encryptJson(new PrivateAddress(name, phone, detail, latitude, longitude, mapAddress, doorDetail), "addresses.private"),
                isDefault, tag, id, userId) == 1;
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

    @org.springframework.transaction.annotation.Transactional
    public void reencrypt(long id) {
        String stored = jdbc.queryForObject("SELECT private_data_encrypted FROM addresses WHERE id=? FOR UPDATE", String.class, id);
        if (crypto.isCurrent(stored)) return;
        Address address = jdbc.query("SELECT * FROM addresses WHERE id=?", MAPPER, id).getFirst();
        var data = new PrivateAddress(address.name(), address.phone(), address.detail(), address.latitude(), address.longitude(), address.mapAddress(), address.doorDetail());
        jdbc.update("UPDATE addresses SET name='',phone='',detail='',latitude=NULL,longitude=NULL,map_address='',door_detail='',private_data_encrypted=? WHERE id=?",
                crypto.encryptJson(data, "addresses.private"), id);
    }
}
