package com.example.takeout.dao;

import com.example.takeout.model.Review;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * 评价数据访问
 */
@Repository
public class ReviewDao {

    private static final RowMapper<Review> MAPPER = (rs, i) -> new Review(
            rs.getLong("id"),
            rs.getLong("store_id"),
            rs.getLong("user_id"),
            rs.getString("user_name"),
            rs.getInt("rating"),
            rs.getString("content"),
            rs.getString("tags"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public ReviewDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Review> listByStore(long storeId) {
        return jdbc.query("SELECT * FROM reviews WHERE store_id = ? ORDER BY id DESC", MAPPER, storeId);
    }

    public long insert(long storeId, long userId, String userName, int rating, String content,
                       String tagsJson, String now) {
        jdbc.update("INSERT INTO reviews(store_id, user_id, user_name, rating, content, tags, create_time) VALUES(?,?,?,?,?,?,?)",
                storeId, userId, userName, rating, content, tagsJson, now);
        return jdbc.queryForObject("SELECT last_insert_rowid()", Long.class);
    }
}
