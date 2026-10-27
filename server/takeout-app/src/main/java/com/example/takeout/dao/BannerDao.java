package com.example.takeout.dao;

import com.example.takeout.model.Banner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * 首页轮播 Banner 数据访问
 */
@Repository
public class BannerDao {

    private static final RowMapper<Banner> MAPPER = (rs, i) -> new Banner(
            rs.getLong("id"),
            rs.getString("title"),
            rs.getString("subtitle"),
            rs.getString("image"),
            rs.getString("color"),
            rs.getString("link_type"),
            rs.getString("link_value"),
            rs.getInt("sort"),
            rs.getInt("status"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public BannerDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Banner> listActive() {
        return jdbc.query("SELECT * FROM banners WHERE status = 1 AND deleted = 0 ORDER BY sort, id DESC", MAPPER);
    }

    public List<Banner> listAll() {
        return jdbc.query("SELECT * FROM banners WHERE deleted = 0 ORDER BY sort, id DESC", MAPPER);
    }

    public long insert(String title, String subtitle, String image, String color,
                       String linkType, String linkValue, int sort, String now) {
        jdbc.update("INSERT INTO banners(title, subtitle, image, color, link_type, link_value, sort, status, create_time) VALUES(?,?,?,?,?,?,?,1,?)",
                title, subtitle, image, color, linkType, linkValue, sort, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void update(long id, String title, String subtitle, String image, String color,
                       String linkType, String linkValue, int sort) {
        jdbc.update("UPDATE banners SET title=?, subtitle=?, image=?, color=?, link_type=?, link_value=?, sort=? WHERE id=?",
                title, subtitle, image, color, linkType, linkValue, sort, id);
    }

    public void updateStatus(long id, int status) {
        jdbc.update("UPDATE banners SET status = ? WHERE id = ?", status, id);
    }

    public void delete(long id) {
        jdbc.update("UPDATE banners SET deleted = 1 WHERE id = ?", id);
    }

    public Optional<Banner> findById(long id) {
        return jdbc.query("SELECT * FROM banners WHERE id = ?", MAPPER, id).stream().findFirst();
    }
}
