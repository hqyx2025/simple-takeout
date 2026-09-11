package com.example.takeout.dao;

import com.example.takeout.model.Announcement;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * 平台公告数据访问
 */
@Repository
public class AnnouncementDao {

    private static final RowMapper<Announcement> MAPPER = (rs, i) -> new Announcement(
            rs.getLong("id"),
            rs.getString("title"),
            rs.getString("content"),
            rs.getInt("status"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public AnnouncementDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Announcement> listActive() {
        return jdbc.query("SELECT * FROM announcements WHERE status = 1 ORDER BY id DESC", MAPPER);
    }

    public List<Announcement> listAll() {
        return jdbc.query("SELECT * FROM announcements ORDER BY id DESC", MAPPER);
    }

    public long insert(String title, String content, String now) {
        jdbc.update("INSERT INTO announcements(title, content, status, create_time) VALUES(?,?,1,?)",
                title, content, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void updateStatus(long id, int status) {
        jdbc.update("UPDATE announcements SET status = ? WHERE id = ?", status, id);
    }

    public void delete(long id) {
        jdbc.update("DELETE FROM announcements WHERE id = ?", id);
    }

    public Optional<Announcement> findById(long id) {
        return jdbc.query("SELECT * FROM announcements WHERE id = ?", MAPPER, id).stream().findFirst();
    }
}
