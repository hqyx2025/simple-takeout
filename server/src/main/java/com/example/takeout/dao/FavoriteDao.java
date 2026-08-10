package com.example.takeout.dao;

import com.example.takeout.model.Favorite;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * 收藏数据访问
 */
@Repository
public class FavoriteDao {

    private static final RowMapper<Favorite> MAPPER = (rs, i) -> new Favorite(
            rs.getLong("id"),
            rs.getLong("user_id"),
            rs.getLong("store_id"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public FavoriteDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Favorite> listByUser(long userId) {
        return jdbc.query("SELECT * FROM favorites WHERE user_id = ? ORDER BY id DESC", MAPPER, userId);
    }

    public boolean exists(long userId, long storeId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM favorites WHERE user_id = ? AND store_id = ?",
                Integer.class, userId, storeId);
        return count != null && count > 0;
    }

    public long insert(long userId, long storeId, String now) {
        jdbc.update("INSERT INTO favorites(user_id, store_id, create_time) VALUES(?,?,?)", userId, storeId, now);
        return jdbc.queryForObject("SELECT last_insert_rowid()", Long.class);
    }

    public void delete(long userId, long storeId) {
        jdbc.update("DELETE FROM favorites WHERE user_id = ? AND store_id = ?", userId, storeId);
    }
}
