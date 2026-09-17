package com.example.takeout.dao;

import com.example.takeout.model.Rider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * 骑手数据访问（四端改造）
 */
@Repository
public class RiderDao {

    private static final RowMapper<Rider> MAPPER = (rs, i) -> new Rider(
            rs.getLong("id"),
            rs.getLong("user_id"),
            rs.getString("name"),
            rs.getString("phone"),
            rs.getInt("online"),
            rs.getInt("total_orders"),
            rs.getDouble("total_income"),
            rs.getInt("status"),
            rs.getInt("delivery_radius"),
            rs.getObject("latitude", Double.class),
            rs.getObject("longitude", Double.class),
            rs.getString("location_address"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public RiderDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<Rider> findById(long id) {
        return jdbc.query("SELECT * FROM riders WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public Optional<Rider> findByUserId(long userId) {
        return jdbc.query("SELECT * FROM riders WHERE user_id = ?", MAPPER, userId).stream().findFirst();
    }

    public long insert(long userId, String name, String phone, String now) {
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
    public boolean updateLocation(long id, double latitude, double longitude, String address) {
        return jdbc.update("UPDATE riders SET latitude = ?, longitude = ?, location_address = ? WHERE id = ?",
                latitude, longitude, address, id) == 1;
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
