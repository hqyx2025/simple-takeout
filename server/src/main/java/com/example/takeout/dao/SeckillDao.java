package com.example.takeout.dao;

import com.example.takeout.model.Seckill;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Optional;

/**
 * 限时秒杀数据访问。
 * 秒杀面向「单品」：多规格菜品参与秒杀时规格价与秒杀价语义冲突，因此只对无规格菜品生效。
 */
@Repository
public class SeckillDao {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /** 秒杀时间窗口 SQL 片段（start_time / end_time 为 VARCHAR，格式统一 yyyy-MM-dd HH:mm:ss）。 */
    private static final String IN_WINDOW = " AND ? BETWEEN start_time AND end_time ";

    private static final RowMapper<Seckill> MAPPER = (rs, i) -> new Seckill(
            rs.getLong("id"),
            rs.getLong("goods_id"),
            rs.getLong("store_id"),
            rs.getDouble("price"),
            rs.getInt("quota"),
            rs.getInt("sold"),
            rs.getString("start_time"),
            rs.getString("end_time"),
            rs.getInt("status"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public SeckillDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** 进行中的秒杀（前端秒杀专区）：秒杀价比菜品现价更低、有名额且菜品/店铺在售。 */
    public List<Seckill.SeckillView> listActiveViews(int limit, String now) {
        return jdbc.query("SELECT s.*, g.name AS goods_name, g.image AS goods_image, " +
                        "g.original_price AS goods_original_price, g.price AS goods_price, " +
                        "st.name AS store_name, st.distance AS store_distance, " +
                        "TIMESTAMPDIFF(SECOND, ?, STR_TO_DATE(s.end_time, '%Y-%m-%d %H:%i:%s')) AS remain_seconds " +
                        "FROM seckills s " +
                        "JOIN goods g ON g.id = s.goods_id " +
                        "JOIN stores st ON st.id = s.store_id " +
                        "WHERE s.status = 1 AND g.status = 1 AND st.status = 1 " +
                        "AND s.sold < s.quota " + IN_WINDOW +
                        "AND NOT EXISTS (SELECT 1 FROM goods_specs sp WHERE sp.goods_id = g.id AND sp.status = 1) " +
                        "ORDER BY s.end_time, s.id LIMIT ?",
                (rs, i) -> new Seckill.SeckillView(
                        rs.getLong("id"),
                        rs.getLong("goods_id"),
                        rs.getString("goods_name"),
                        rs.getString("goods_image"),
                        rs.getDouble("goods_original_price") > 0
                                ? rs.getDouble("goods_original_price") : rs.getDouble("goods_price"),
                        rs.getDouble("price"),
                        rs.getInt("quota"),
                        rs.getInt("sold"),
                        rs.getString("start_time"),
                        rs.getString("end_time"),
                        rs.getLong("store_id"),
                        rs.getString("store_name"),
                        rs.getString("store_distance"),
                        Math.max(rs.getLong("remain_seconds"), 0)),
                now, now, limit);
    }

    /** 菜品当前生效的秒杀（下单时自动套用秒杀价）。 */
    public Optional<Seckill> findActiveByGoods(long goodsId, String now) {
        return jdbc.query("SELECT * FROM seckills WHERE goods_id = ? AND status = 1 AND sold < quota " + IN_WINDOW +
                        " ORDER BY price LIMIT 1", MAPPER, goodsId, now).stream().findFirst();
    }

    public List<Seckill> listAll() {
        return jdbc.query("SELECT * FROM seckills ORDER BY id DESC", MAPPER);
    }

    public Optional<Seckill> findById(long id) {
        return jdbc.query("SELECT * FROM seckills WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public long insert(long goodsId, long storeId, double price, int quota, String startTime, String endTime, int status) {
        jdbc.update("INSERT INTO seckills(goods_id, store_id, price, quota, sold, start_time, end_time, status, create_time) " +
                        "VALUES(?,?,?,?,0,?,?,?,?)",
                goodsId, storeId, price, quota, startTime, endTime, status, LocalDateTime.now().format(FMT));
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void update(long id, double price, int quota, String startTime, String endTime, int status) {
        jdbc.update("UPDATE seckills SET price = ?, quota = ?, start_time = ?, end_time = ?, status = ? WHERE id = ?",
                price, quota, startTime, endTime, status, id);
    }

    public void delete(long id) {
        jdbc.update("DELETE FROM seckills WHERE id = ?", id);
    }

    /** 占用秒杀名额（条件更新，名额不足返回 false）。 */
    public boolean deductQuota(long id, int quantity, String now) {
        return jdbc.update("UPDATE seckills SET sold = sold + ? WHERE id = ? AND status = 1 " +
                        "AND sold + ? <= quota " + IN_WINDOW,
                quantity, id, quantity, now) == 1;
    }

    /** 释放秒杀名额（取消/超时未支付取消订单时回滚）。 */
    public void restoreQuota(long id, int quantity) {
        jdbc.update("UPDATE seckills SET sold = GREATEST(sold - ?, 0) WHERE id = ?", quantity, id);
    }
}
