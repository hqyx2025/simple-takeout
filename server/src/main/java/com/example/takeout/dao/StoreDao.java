package com.example.takeout.dao;

import com.example.takeout.model.Category;
import com.example.takeout.model.Store;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * 店铺与分类数据访问
 */
@Repository
public class StoreDao {

    private static final RowMapper<Store> MAPPER = (rs, i) -> new Store(
            rs.getLong("id"),
            rs.getString("name"),
            rs.getString("image"),
            rs.getDouble("rating"),
            rs.getInt("monthly_sales"),
            rs.getDouble("delivery_fee"),
            rs.getDouble("min_order"),
            rs.getString("delivery_time"),
            rs.getString("distance"),
            rs.getString("tags"),
            rs.getString("notice"),
            rs.getInt("category_id"),
            rs.getString("category_ids"),
            rs.getLong("owner_id"),
            rs.getInt("status"),
            rs.getString("create_time")
    );

    private static final RowMapper<Category> CATEGORY_MAPPER = (rs, i) -> new Category(
            rs.getLong("id"),
            rs.getString("name"),
            rs.getString("icon"),
            rs.getString("color")
    );

    private final JdbcTemplate jdbc;

    public StoreDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Category> listCategories() {
        return jdbc.query("SELECT * FROM categories ORDER BY id", CATEGORY_MAPPER);
    }

    public Optional<Category> findCategoryById(long categoryId) {
        return jdbc.query("SELECT * FROM categories WHERE id = ?", CATEGORY_MAPPER, categoryId)
                .stream().findFirst();
    }

    public boolean categoryNameExists(String name, long excludeId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM categories WHERE name = ? AND id <> ?",
                Integer.class, name, excludeId);
        return count != null && count > 0;
    }

    public long insertCategory(String name, String icon, String color) {
        jdbc.update("INSERT INTO categories(name, icon, color) VALUES(?,?,?)", name, icon, color);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void updateCategory(long id, String name, String icon, String color) {
        jdbc.update("UPDATE categories SET name=?, icon=?, color=? WHERE id=?", name, icon, color, id);
    }

    public void deleteCategory(long id) {
        jdbc.update("DELETE FROM categories WHERE id = ?", id);
    }

    public int countStoresByCategory(long categoryId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM stores WHERE category_id = ? OR " +
                "JSON_CONTAINS(COALESCE(category_ids, '[]'), JSON_ARRAY(?))", Integer.class, categoryId, categoryId);
        return count == null ? 0 : count;
    }

    public List<Store> listAll() {
        return jdbc.query("SELECT * FROM stores WHERE status = 1 ORDER BY monthly_sales DESC", MAPPER);
    }

    public List<Store> listAllForAdmin() {
        return jdbc.query("SELECT * FROM stores ORDER BY id DESC", MAPPER);
    }

    public List<Store> listByCategory(int categoryId) {
        return jdbc.query("SELECT * FROM stores WHERE status = 1 AND " +
                        "(category_id = ? OR JSON_CONTAINS(COALESCE(category_ids, '[]'), JSON_ARRAY(?))) " +
                        "ORDER BY monthly_sales DESC",
                MAPPER, categoryId, categoryId);
    }

    public boolean categoryExists(long categoryId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM categories WHERE id = ?", Integer.class, categoryId);
        return count != null && count > 0;
    }

    public List<Store> listByOwner(long ownerId) {
        return jdbc.query("SELECT * FROM stores WHERE owner_id = ? ORDER BY id", MAPPER, ownerId);
    }

    public Optional<Store> findById(long id) {
        return jdbc.query("SELECT * FROM stores WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public long insert(Store s) {
        jdbc.update("INSERT INTO stores(name, image, rating, monthly_sales, delivery_fee, min_order, delivery_time, distance, tags, notice, category_id, category_ids, owner_id, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                s.name(), s.image(), s.rating(), s.monthlySales(), s.deliveryFee(), s.minOrder(),
                s.deliveryTime(), s.distance(), s.tags(), s.notice(), s.categoryId(), s.categoryIds(),
                s.ownerId(), s.status(), s.createTime());
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void update(Store s) {
        jdbc.update("UPDATE stores SET name=?, image=?, rating=?, monthly_sales=?, delivery_fee=?, min_order=?, delivery_time=?, distance=?, tags=?, notice=?, category_id=?, category_ids=?, status=? WHERE id=?",
                s.name(), s.image(), s.rating(), s.monthlySales(), s.deliveryFee(), s.minOrder(),
                s.deliveryTime(), s.distance(), s.tags(), s.notice(), s.categoryId(), s.categoryIds(),
                s.status(), s.id());
    }

    public void updateMonthlySales(long storeId, int sales) {
        jdbc.update("UPDATE stores SET monthly_sales = monthly_sales + ? WHERE id = ?", sales, storeId);
    }

    public void updateStatus(long storeId, int status) {
        jdbc.update("UPDATE stores SET status = ? WHERE id = ?", status, storeId);
    }
}
