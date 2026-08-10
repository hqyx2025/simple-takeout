package com.example.takeout.dao;

import com.example.takeout.model.Goods;
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

    public Optional<Goods> findById(long id) {
        return jdbc.query("SELECT * FROM goods WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public long insert(Goods g) {
        jdbc.update("INSERT INTO goods(store_id, name, description, price, original_price, image, category_id, sales, rating, tag, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                g.storeId(), g.name(), g.description(), g.price(), g.originalPrice(), g.image(),
                g.categoryId(), g.sales(), g.rating(), g.tag(), g.status(), g.createTime());
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void update(Goods g) {
        jdbc.update("UPDATE goods SET name=?, description=?, price=?, original_price=?, image=?, category_id=?, tag=?, status=? WHERE id=?",
                g.name(), g.description(), g.price(), g.originalPrice(), g.image(),
                g.categoryId(), g.tag(), g.status(), g.id());
    }

    public void delete(long id) {
        jdbc.update("DELETE FROM goods WHERE id = ?", id);
    }
}
