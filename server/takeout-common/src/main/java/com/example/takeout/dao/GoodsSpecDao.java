package com.example.takeout.dao;

import com.example.takeout.model.GoodsSpec;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Optional;

/**
 * 菜品规格数据访问（多规格 SKU）
 */
@Repository
public class GoodsSpecDao {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private static final RowMapper<GoodsSpec> MAPPER = (rs, i) -> new GoodsSpec(
            rs.getLong("id"),
            rs.getLong("goods_id"),
            rs.getString("name"),
            rs.getDouble("price"),
            rs.getInt("stock"),
            rs.getInt("version"),
            rs.getInt("sort"),
            rs.getInt("status"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public GoodsSpecDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<GoodsSpec> listByGoods(long goodsId) {
        return jdbc.query("SELECT * FROM goods_specs WHERE goods_id = ? AND status = 1 ORDER BY sort, id",
                MAPPER, goodsId);
    }

    public List<GoodsSpec> listByGoodsIds(List<Long> goodsIds) {
        if (goodsIds == null || goodsIds.isEmpty()) {
            return List.of();
        }
        String placeholders = String.join(",", goodsIds.stream().map(id -> "?").toList());
        return jdbc.query("SELECT * FROM goods_specs WHERE status = 1 AND goods_id IN (" + placeholders + ") " +
                "ORDER BY goods_id, sort, id", MAPPER, goodsIds.toArray());
    }

    public Optional<GoodsSpec> findById(long id) {
        return jdbc.query("SELECT * FROM goods_specs WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public long insert(long goodsId, String name, double price, int stock, int sort) {
        jdbc.update("INSERT INTO goods_specs(goods_id, name, price, stock, version, sort, status, create_time) " +
                        "VALUES(?,?,?,?,0,?,1,?)",
                goodsId, name, price, stock, sort, LocalDateTime.now().format(FMT));
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void update(long id, String name, double price, int stock, int sort) {
        jdbc.update("UPDATE goods_specs SET name = ?, price = ?, stock = ?, sort = ? WHERE id = ?",
                name, price, stock, sort, id);
    }

    public void deleteByGoods(long goodsId) {
        jdbc.update("DELETE FROM goods_specs WHERE goods_id = ?", goodsId);
    }

    public void deleteByIds(List<Long> ids) {
        if (ids == null || ids.isEmpty()) {
            return;
        }
        String placeholders = String.join(",", ids.stream().map(id -> "?").toList());
        jdbc.update("DELETE FROM goods_specs WHERE id IN (" + placeholders + ")", ids.toArray());
    }

    /** 扣减规格库存（乐观锁条件更新，防超卖）。 */
    public boolean deductStock(long specId, int quantity) {
        return jdbc.update("UPDATE goods_specs SET stock = stock - ?, version = version + 1 " +
                "WHERE id = ? AND stock >= ? AND status = 1", quantity, specId, quantity) == 1;
    }

    /** 回滚规格库存（取消订单/超时取消时恢复）。 */
    public void restoreStock(long specId, int quantity) {
        jdbc.update("UPDATE goods_specs SET stock = stock + ? WHERE id = ?", quantity, specId);
    }
}
