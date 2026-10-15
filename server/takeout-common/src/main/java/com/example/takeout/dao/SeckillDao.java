package com.example.takeout.dao;

import com.example.takeout.model.Seckill;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.ArrayList;
import java.util.Optional;

/**
 * 限时秒杀数据访问。
 * 秒杀面向「单品」：多规格菜品参与秒杀时规格价与秒杀价语义冲突，因此只对无规格菜品生效。
 */
@Repository
public class SeckillDao {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /** Typed comparison with legacy-only and older-instance edits handled explicitly. */
    private static final String IN_WINDOW = " AND " + JdbcDateTimes.PARAMETER + " BETWEEN " +
            JdbcDateTimes.value("start_time") + " AND " + JdbcDateTimes.value("end_time") + " ";

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
                        "TIMESTAMPDIFF(SECOND, " + JdbcDateTimes.PARAMETER + ", " +
                        JdbcDateTimes.value("s.end_time") + ") AS remain_seconds " +
                        "FROM seckills s " +
                        "JOIN goods g ON g.id = s.goods_id " +
                        "JOIN stores st ON st.id = s.store_id " +
                        "WHERE s.status = 1 AND g.status = 1 AND st.status = 1 " +
                        "AND s.sold < s.quota " + IN_WINDOW +
                        "AND NOT EXISTS (SELECT 1 FROM goods_specs sp WHERE sp.goods_id = g.id AND sp.status = 1) " +
                        "ORDER BY " + JdbcDateTimes.value("s.end_time") + ", s.id LIMIT ?",
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

    public List<Seckill> listByStore(long storeId) {
        return jdbc.query("SELECT * FROM seckills WHERE store_id = ? ORDER BY id DESC", MAPPER, storeId);
    }

    /** 平台监管秒杀列表；storeId 为空时返回全部店铺。 */
    public List<Seckill> listForAdmin(Long storeId) {
        return listForAdmin(storeId, null);
    }

    /** 平台监管秒杀列表，可按店铺与上下架状态筛选。 */
    public List<Seckill> listForAdmin(Long storeId, Integer status) {
        StringBuilder sql = new StringBuilder("SELECT * FROM seckills WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (storeId != null) {
            sql.append(" AND store_id = ?");
            args.add(storeId);
        }
        if (status != null) {
            sql.append(" AND status = ?");
            args.add(status);
        }
        sql.append(" ORDER BY id DESC");
        return jdbc.query(sql.toString(), MAPPER, args.toArray());
    }

    public Optional<Seckill> findById(long id) {
        return jdbc.query("SELECT * FROM seckills WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public long insert(long goodsId, long storeId, double price, int quota, String startTime, String endTime, int status) {
        String now = LocalDateTime.now().format(FMT);
        jdbc.update("INSERT INTO seckills(goods_id, store_id, price, quota, sold, start_time, end_time, status, " +
                        "create_time, start_time_dt, end_time_dt, create_time_dt) VALUES(?,?,?,?,0,?,?,?,?," +
                        JdbcDateTimes.PARAMETER + "," + JdbcDateTimes.PARAMETER + "," + JdbcDateTimes.PARAMETER + ")",
                goodsId, storeId, price, quota, startTime, endTime, status, now, startTime, endTime, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void update(long id, double price, int quota, String startTime, String endTime, int status) {
        jdbc.update("UPDATE seckills SET price = ?, quota = ?, start_time = ?, end_time = ?, status = ?, " +
                        "start_time_dt = " + JdbcDateTimes.PARAMETER + ", end_time_dt = " + JdbcDateTimes.PARAMETER +
                        " WHERE id = ?",
                price, quota, startTime, endTime, status, startTime, endTime, id);
    }

    public void update(long id, long storeId, double price, int quota, String startTime, String endTime, int status) {
        jdbc.update("UPDATE seckills SET price = ?, quota = ?, start_time = ?, end_time = ?, status = ?, " +
                        "start_time_dt = " + JdbcDateTimes.PARAMETER + ", end_time_dt = " + JdbcDateTimes.PARAMETER +
                        " WHERE id = ? AND store_id = ?",
                price, quota, startTime, endTime, status, startTime, endTime, id, storeId);
    }

    public void delete(long id) {
        jdbc.update("DELETE FROM seckills WHERE id = ?", id);
    }

    /** 管理端删除前再次原子确认还没有销量，避免与下单扣减并发时越过销售保护。 */
    public boolean deleteIfUnsold(long id) {
        return jdbc.update("DELETE FROM seckills WHERE id = ? AND sold = 0", id) == 1;
    }

    public void delete(long id, long storeId) {
        jdbc.update("DELETE FROM seckills WHERE id = ? AND store_id = ?", id, storeId);
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

    /**
     * 登记「一人一单」参与记录：INSERT IGNORE 依赖唯一键 (user_id, seckill_id)，
     * 同一用户对同一场秒杀重复下单时返回 false（0 行受影响），由调用方回滚整单。
     */
    public boolean joinOnce(long userId, long seckillId, long orderId, String now) {
        return jdbc.update("INSERT IGNORE INTO seckill_orders(user_id, seckill_id, order_id, create_time, create_time_dt) " +
                "VALUES(?,?,?,?," + JdbcDateTimes.PARAMETER + ")", userId, seckillId, orderId, now, now) == 1;
    }

    /** 释放「一人一单」资格（取消/超时未支付回滚时与名额一并释放）。 */
    public void releaseOnce(long userId, long seckillId) {
        jdbc.update("DELETE FROM seckill_orders WHERE user_id = ? AND seckill_id = ?", userId, seckillId);
    }
}
