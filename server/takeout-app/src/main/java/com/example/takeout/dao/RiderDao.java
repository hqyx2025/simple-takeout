package com.example.takeout.dao;

import com.example.takeout.model.Rider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;
import com.example.takeout.service.PersonalDataCrypto;

import java.util.List;
import java.util.Optional;

/**
 * 骑手数据访问（四端改造）
 */
@Repository
public class RiderDao {

    private final RowMapper<Rider> MAPPER = (rs, i) -> {
        PrivateRider data = readPrivate(rs);
        return new Rider(
            rs.getLong("id"),
            rs.getLong("user_id"),
            data.name(),
            data.phone(),
            rs.getInt("online"),
            rs.getInt("total_orders"),
            rs.getDouble("total_income"),
            rs.getInt("status"),
            rs.getInt("delivery_radius"),
            data.latitude(),
            data.longitude(),
            data.address(),
            rs.getString("create_time")
    ); };

    public record PrivateRider(String name, String phone, Double latitude, Double longitude, String address) {
        @Override public String toString() { return "PrivateRider[redacted]"; }
    }

    private final JdbcTemplate jdbc;
    private final PersonalDataCrypto crypto;

    public RiderDao(JdbcTemplate jdbc) {
        this(jdbc, null);
    }

    @org.springframework.beans.factory.annotation.Autowired
    public RiderDao(JdbcTemplate jdbc, PersonalDataCrypto crypto) {
        this.jdbc = jdbc; this.crypto = crypto;
    }

    private PrivateRider readPrivate(java.sql.ResultSet row) throws java.sql.SQLException {
        String encrypted = crypto == null ? null : row.getString("private_data_encrypted");
        if (encrypted != null) return crypto.decryptJson(encrypted, "riders.private", PrivateRider.class);
        return new PrivateRider(row.getString("name"), row.getString("phone"), row.getObject("latitude", Double.class),
                row.getObject("longitude", Double.class), row.getString("location_address"));
    }

    public Optional<Rider> findById(long id) {
        return jdbc.query("SELECT * FROM riders WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public Optional<Rider> findByUserId(long userId) {
        return jdbc.query("SELECT * FROM riders WHERE user_id = ?", MAPPER, userId).stream().findFirst();
    }

    @org.springframework.transaction.annotation.Transactional
    public long insert(long userId, String name, String phone, String now) {
        if (crypto != null) {
            jdbc.update("INSERT INTO riders(user_id,name,phone,online,total_orders,total_income,status,create_time,private_data_encrypted) VALUES(?,'','',0,0,0,1,?,?)",
                    userId, now, crypto.encryptJson(new PrivateRider(name, phone, null, null, ""), "riders.private"));
            return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        }
        jdbc.update("INSERT INTO riders(user_id, name, phone, online, total_orders, total_income, status, create_time) VALUES(?,?,?,0,0,0,1,?)",
                userId, name, phone, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public boolean updateOnline(long id, int online) {
        return jdbc.update("UPDATE riders SET online = ? WHERE id = ?", online, id) == 1;
    }

    public boolean updateStatus(long id, int status) {
        return jdbc.update("UPDATE riders SET status = ? WHERE id = ?", status, id) == 1;
    }

    /** 骑手配送半径（米）。 */
    public boolean updateDeliveryRadius(long id, int radiusMeters) {
        return jdbc.update("UPDATE riders SET delivery_radius = ? WHERE id = ?", radiusMeters, id) == 1;
    }

    /** 骑手接单位置（抢单圆心）。 */
    @org.springframework.transaction.annotation.Transactional
    public boolean updateLocation(long id, double latitude, double longitude, String address) {
        if (crypto != null) {
            List<Rider> rows = jdbc.query("SELECT * FROM riders WHERE id=? FOR UPDATE", MAPPER, id);
            if (rows.isEmpty()) return false;
            Rider rider = rows.getFirst();
            return jdbc.update("UPDATE riders SET name='',phone='',latitude=NULL,longitude=NULL,location_address='',private_data_encrypted=? WHERE id=?",
                    crypto.encryptJson(new PrivateRider(rider.name(), rider.phone(), latitude, longitude, address), "riders.private"), id) == 1;
        }
        return jdbc.update("UPDATE riders SET latitude = ?, longitude = ?, location_address = ? WHERE id = ?",
                latitude, longitude, address, id) == 1;
    }

    @org.springframework.transaction.annotation.Transactional
    public void reencrypt(long id) {
        String stored = jdbc.queryForObject("SELECT private_data_encrypted FROM riders WHERE id=? FOR UPDATE", String.class, id);
        if (crypto.isCurrent(stored)) return;
        Rider rider = findById(id).orElseThrow();
        jdbc.update("UPDATE riders SET name='',phone='',latitude=NULL,longitude=NULL,location_address='',private_data_encrypted=? WHERE id=?",
                crypto.encryptJson(new PrivateRider(rider.name(), rider.phone(), rider.latitude(), rider.longitude(), rider.locationAddress()), "riders.private"), id);
    }

    /** 送达完成后累加骑手单量与收入。 */
    public void addCompleted(long id, double income) {
        jdbc.update("UPDATE riders SET total_orders = total_orders + 1, total_income = total_income + ? WHERE id = ?",
                income, id);
    }

    public List<Rider> listAll() {
        return jdbc.query("SELECT * FROM riders ORDER BY id DESC", MAPPER);
    }
}
