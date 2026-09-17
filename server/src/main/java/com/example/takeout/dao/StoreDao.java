package com.example.takeout.dao;

import com.example.takeout.model.Category;
import com.example.takeout.model.MarketingActivity;
import com.example.takeout.model.Setmeal;
import com.example.takeout.model.SetmealItem;
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
            rs.getString("address"),
            rs.getObject("latitude", Double.class),
            rs.getObject("longitude", Double.class),
            rs.getInt("category_id"),
            rs.getString("category_ids"),
            rs.getLong("owner_id"),
            rs.getInt("status"),
            rs.getInt("recommended"),
            rs.getString("create_time"),
            rs.getInt("delivery_radius")
    );

    private static final RowMapper<MarketingActivity> MARKETING_MAPPER = (rs, i) -> new MarketingActivity(
            rs.getLong("id"),
            rs.getLong("store_id"),
            rs.getString("type"),
            rs.getString("title"),
            rs.getDouble("discount_rate"),
            rs.getDouble("reduce_amount"),
            rs.getDouble("threshold"),
            rs.getLong("gift_goods_id"),
            rs.getString("start_time"),
            rs.getString("end_time"),
            rs.getInt("status"),
            rs.getString("create_time")
    );

    private static final RowMapper<Setmeal> SETMEAL_MAPPER = (rs, i) -> new Setmeal(
            rs.getLong("id"),
            rs.getLong("store_id"),
            rs.getString("name"),
            rs.getString("description"),
            rs.getDouble("price"),
            rs.getDouble("original_price"),
            rs.getString("image"),
            rs.getInt("status"),
            rs.getString("create_time"),
            List.of()
    );

    private static final RowMapper<SetmealItem> SETMEAL_ITEM_MAPPER = (rs, i) -> new SetmealItem(
            rs.getLong("id"),
            rs.getLong("setmeal_id"),
            rs.getLong("goods_id"),
            rs.getString("goods_name"),
            rs.getInt("quantity")
    );

    private static final RowMapper<Category> CATEGORY_MAPPER = (rs, i) -> new Category(
            rs.getLong("id"),
            rs.getString("name"),
            rs.getString("icon"),
            rs.getString("color"),
            rs.getString("type"),
            rs.getLong("merchant_id"),
            rs.getInt("sort"),
            rs.getInt("status")
    );

    private final JdbcTemplate jdbc;

    public StoreDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** 平台分类（首页导航与店铺/商品创建时选择）。 */
    public List<Category> listCategories() {
        return jdbc.query("SELECT * FROM categories WHERE type = 'PLATFORM' AND status = 1 AND deleted = 0 ORDER BY id", CATEGORY_MAPPER);
    }

    public Optional<Category> findCategoryById(long categoryId) {
        return jdbc.query("SELECT * FROM categories WHERE id = ? AND deleted = 0", CATEGORY_MAPPER, categoryId)
                .stream().findFirst();
    }

    public boolean categoryNameExists(String name, long excludeId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM categories WHERE name = ? AND id <> ? AND type = 'PLATFORM' AND deleted = 0",
                Integer.class, name, excludeId);
        return count != null && count > 0;
    }

    public long insertCategory(String name, String icon, String color) {
        jdbc.update("INSERT INTO categories(name, icon, color, type) VALUES(?,?,?,'PLATFORM')", name, icon, color);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void updateCategory(long id, String name, String icon, String color) {
        jdbc.update("UPDATE categories SET name=?, icon=?, color=? WHERE id=?", name, icon, color, id);
    }

    public void deleteCategory(long id) {
        jdbc.update("UPDATE categories SET deleted = 1 WHERE id = ?", id);
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

    /** 平台推荐营业店铺，距离由服务层按用户当前坐标计算。 */
    public List<Store> listRecommended() {
        return jdbc.query("SELECT * FROM stores WHERE status = 1 AND recommended = 1 " +
                        "ORDER BY rating DESC, monthly_sales DESC", MAPPER);
    }

    public boolean categoryExists(long categoryId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM categories WHERE id = ? AND type = 'PLATFORM' AND deleted = 0",
                Integer.class, categoryId);
        return count != null && count > 0;
    }

    // ============ 商户分类（演进项，见大纲 8.3） ============

    public List<Category> listMerchantCategories(long merchantId) {
        return jdbc.query("SELECT * FROM categories WHERE type = 'MERCHANT' AND merchant_id = ? " +
                "AND status = 1 AND deleted = 0 ORDER BY sort, id", CATEGORY_MAPPER, merchantId);
    }

    /** 归属校验：商户分类必须属于当前商户用户。 */
    public boolean merchantCategoryOwned(long categoryId, long merchantId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM categories WHERE id = ? AND type = 'MERCHANT' AND merchant_id = ? AND deleted = 0",
                Integer.class, categoryId, merchantId);
        return count != null && count > 0;
    }

    public boolean merchantCategoryNameExists(long merchantId, String name, long excludeId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM categories WHERE type = 'MERCHANT' AND merchant_id = ? AND name = ? AND id <> ? AND deleted = 0",
                Integer.class, merchantId, name, excludeId);
        return count != null && count > 0;
    }

    public long insertMerchantCategory(long merchantId, String name, int sort) {
        jdbc.update("INSERT INTO categories(name, icon, color, type, merchant_id, sort, status) VALUES(?,'','','MERCHANT',?,?,1)",
                name, merchantId, sort);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void updateMerchantCategory(long id, String name, int sort) {
        jdbc.update("UPDATE categories SET name = ?, sort = ? WHERE id = ?", name, sort, id);
    }

    public void deleteMerchantCategory(long id) {
        jdbc.update("UPDATE categories SET deleted = 1 WHERE id = ?", id);
    }

    /** 分类下商品引用计数（删除分类前校验）。 */
    public int countGoodsByMerchantCategory(long categoryId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM goods WHERE merchant_category_id = ? AND deleted = 0", Integer.class, categoryId);
        return count == null ? 0 : count;
    }

    public List<Store> listByOwner(long ownerId) {
        return jdbc.query("SELECT * FROM stores WHERE owner_id = ? ORDER BY id", MAPPER, ownerId);
    }

    public Optional<Store> findById(long id) {
        return jdbc.query("SELECT * FROM stores WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public long insert(Store s) {
        jdbc.update("INSERT INTO stores(name, image, rating, monthly_sales, delivery_fee, min_order, delivery_time, distance, tags, notice, address, latitude, longitude, delivery_radius, category_id, category_ids, owner_id, status, recommended, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                s.name(), s.image(), s.rating(), s.monthlySales(), s.deliveryFee(), s.minOrder(),
                s.deliveryTime(), s.distance(), s.tags(), s.notice(), s.address(), s.latitude(), s.longitude(),
                s.deliveryRadius(), s.categoryId(), s.categoryIds(), s.ownerId(), s.status(), s.recommended(), s.createTime());
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public void update(Store s) {
        jdbc.update("UPDATE stores SET name=?, image=?, rating=?, monthly_sales=?, delivery_fee=?, min_order=?, delivery_time=?, distance=?, tags=?, notice=?, address=?, latitude=?, longitude=?, delivery_radius=?, category_id=?, category_ids=?, status=?, recommended=? WHERE id=?",
                s.name(), s.image(), s.rating(), s.monthlySales(), s.deliveryFee(), s.minOrder(),
                s.deliveryTime(), s.distance(), s.tags(), s.notice(), s.address(), s.latitude(), s.longitude(),
                s.deliveryRadius(), s.categoryId(), s.categoryIds(), s.status(), s.recommended(), s.id());
    }

    public void updateMonthlySales(long storeId, int sales) {
        jdbc.update("UPDATE stores SET monthly_sales = monthly_sales + ? WHERE id = ?", sales, storeId);
    }

    public void updateStatus(long storeId, int status) {
        jdbc.update("UPDATE stores SET status = ? WHERE id = ?", status, storeId);
    }

    public void updateRecommended(long storeId, int recommended) {
        jdbc.update("UPDATE stores SET recommended = ? WHERE id = ?", recommended, storeId);
    }

    /** 评价后重算店铺平均评分（保留一位小数）。 */
    public void updateRating(long storeId, double rating) {
        jdbc.update("UPDATE stores SET rating = ? WHERE id = ?", rating, storeId);
    }

    // ============ 营销活动 ============

    /** 当前生效的活动（status=1 且在时间窗内）。 */
    public List<MarketingActivity> listActiveMarketingActivities(long storeId, String now) {
        return jdbc.query("SELECT * FROM marketing_activities WHERE store_id = ? AND status = 1 AND start_time <= ? AND end_time >= ? ORDER BY id",
                MARKETING_MAPPER, storeId, now, now);
    }

    public List<MarketingActivity> listMarketingActivities(long storeId) {
        return jdbc.query("SELECT * FROM marketing_activities WHERE store_id = ? ORDER BY id DESC",
                MARKETING_MAPPER, storeId);
    }

    public long insertMarketingActivity(MarketingActivity a) {
        jdbc.update("INSERT INTO marketing_activities(store_id, type, title, discount_rate, reduce_amount, threshold, gift_goods_id, start_time, end_time, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                a.storeId(), a.type(), a.title(), a.discountRate(), a.reduceAmount(), a.threshold(),
                a.giftGoodsId(), a.startTime(), a.endTime(), a.status(), a.createTime());
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    // ============ 套餐与组合购 ============

    /** 套餐列表（activeOnly=true 只返上架套餐；items 逐套餐补齐，店铺套餐量级小）。 */
    public List<Setmeal> listSetmealsByStore(long storeId, boolean activeOnly) {
        String sql = "SELECT * FROM setmeals WHERE store_id = ?" + (activeOnly ? " AND status = 1" : "") + " ORDER BY id DESC";
        return jdbc.query(sql, SETMEAL_MAPPER, storeId).stream()
                .map(s -> s.withItems(listSetmealItems(s.id())))
                .toList();
    }

    public long insertSetmeal(Setmeal s) {
        jdbc.update("INSERT INTO setmeals(store_id, name, description, price, original_price, image, status, create_time) VALUES(?,?,?,?,?,?,?,?)",
                s.storeId(), s.name(), s.description(), s.price(), s.originalPrice(), s.image(), s.status(), s.createTime());
        long id = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        for (SetmealItem item : s.items()) {
            jdbc.update("INSERT INTO setmeal_items(setmeal_id, goods_id, goods_name, quantity) VALUES(?,?,?,?)",
                    id, item.goodsId(), item.goodsName(), item.quantity());
        }
        return id;
    }

    public void deleteSetmeal(long setmealId) {
        jdbc.update("DELETE FROM setmeal_items WHERE setmeal_id = ?", setmealId);
        jdbc.update("DELETE FROM setmeals WHERE id = ?", setmealId);
    }

    private List<SetmealItem> listSetmealItems(long setmealId) {
        return jdbc.query("SELECT * FROM setmeal_items WHERE setmeal_id = ? ORDER BY id", SETMEAL_ITEM_MAPPER, setmealId);
    }
}
