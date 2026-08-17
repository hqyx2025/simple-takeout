package com.example.takeout.dao;

import com.example.takeout.model.Goods;
import com.example.takeout.model.AdminProduct;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * 商品数据访问
 */
@Repository
public class GoodsDao {

    private static final RowMapper<Goods> MAPPER = (rs, i) -> new Goods(
            rs.getLong("id"),
            rs.getLong("store_id"),
            rs.getString("name"),
            rs.getString("description"),
            rs.getDouble("price"),
            rs.getDouble("original_price"),
            rs.getString("image"),
            rs.getInt("category_id"),
            rs.getLong("merchant_category_id"),
            rs.getInt("stock"),
            rs.getInt("version"),
            rs.getInt("sales"),
            rs.getDouble("rating"),
            rs.getString("tag"),
            rs.getInt("status"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public GoodsDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Goods> listByStore(long storeId) {
        return jdbc.query("SELECT * FROM goods WHERE store_id = ? AND status = 1 ORDER BY sales DESC", MAPPER, storeId);
    }

    public List<Goods> listByStoreAll(long storeId) {
        return jdbc.query("SELECT * FROM goods WHERE store_id = ? ORDER BY id", MAPPER, storeId);
    }

    public List<AdminProduct> listForAdmin(String keyword, Integer status) {
        StringBuilder sql = new StringBuilder("SELECT g.*, s.name AS store_name FROM goods g " +
                "JOIN stores s ON s.id = g.store_id WHERE 1 = 1");
        List<Object> args = new java.util.ArrayList<>();
        if (keyword != null && !keyword.isBlank()) {
            sql.append(" AND (g.name LIKE ? OR s.name LIKE ?)");
            String value = "%" + keyword.trim() + "%";
            args.add(value);
            args.add(value);
        }
        if (status != null) {
            sql.append(" AND g.status = ?");
            args.add(status);
        }
        sql.append(" ORDER BY g.id DESC");
        return jdbc.query(sql.toString(), (rs, i) -> new AdminProduct(
                rs.getLong("id"), rs.getLong("store_id"), rs.getString("store_name"),
                rs.getString("name"), rs.getString("description"), rs.getDouble("price"),
                rs.getDouble("original_price"), rs.getString("image"), rs.getInt("category_id"),
                rs.getLong("merchant_category_id"), rs.getInt("stock"), rs.getInt("sales"),
                rs.getDouble("rating"), rs.getString("tag"), rs.getInt("status"),
                rs.getString("create_time")
        ), args.toArray());
    }

    public Optional<Goods> findById(long id) {
        return jdbc.query("SELECT * FROM goods WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public long insert(Goods g) {
        jdbc.update("INSERT INTO goods(store_id, name, description, price, original_price, image, category_id, merchant_category_id, stock, version, sales, rating, tag, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                g.storeId(), g.name(), g.description(), g.price(), g.originalPrice(), g.image(),
                g.categoryId(), g.merchantCategoryId(), g.stock(), 0, g.sales(), g.rating(), g.tag(), g.status(), g.createTime());
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void update(Goods g) {
        jdbc.update("UPDATE goods SET name=?, description=?, price=?, original_price=?, image=?, category_id=?, merchant_category_id=?, tag=?, status=?, stock=? WHERE id=?",
                g.name(), g.description(), g.price(), g.originalPrice(), g.image(),
                g.categoryId(), g.merchantCategoryId(), g.tag(), g.status(), g.stock(), g.id());
    }

    /** 快速补货/清库存：直接设置库存（不经过乐观锁）。 */
    public void updateStock(long id, int stock) {
        jdbc.update("UPDATE goods SET stock = ? WHERE id = ?", stock, id);
    }

    public void updateStatus(long id, int status) {
        jdbc.update("UPDATE goods SET status = ? WHERE id = ?", status, id);
    }

    /**
     * 扣减库存（乐观锁条件更新，防超卖）：
     * 更新行数为 0 表示库存不足/已下架，由调用方抛业务异常。
     */
    public boolean deductStock(long id, int quantity) {
        return jdbc.update("UPDATE goods SET stock = stock - ?, version = version + 1 " +
                "WHERE id = ? AND stock >= ? AND status = 1", quantity, id, quantity) == 1;
    }

    /** 回滚库存（取消订单/退款时恢复；仅在 escrow 条件更新成功后的同一事务内调用）。 */
    public void restoreStock(long id, int quantity) {
        jdbc.update("UPDATE goods SET stock = stock + ? WHERE id = ?", quantity, id);
    }

    public void delete(long id) {
        jdbc.update("DELETE FROM goods WHERE id = ?", id);
    }
}
