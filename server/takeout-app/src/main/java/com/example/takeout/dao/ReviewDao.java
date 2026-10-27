package com.example.takeout.dao;

import com.example.takeout.model.Review;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

/**
 * 评价数据访问
 */
@Repository
public class ReviewDao {

    private static final RowMapper<Review> MAPPER = (rs, i) -> new Review(
            rs.getLong("id"),
            rs.getLong("order_id"),
            rs.getLong("store_id"),
            rs.getLong("goods_id"),
            rs.getLong("user_id"),
            rs.getString("user_name"),
            rs.getInt("rating"),
            rs.getString("content"),
            rs.getString("tags"),
            rs.getString("images"),
            rs.getInt("anonymous"),
            rs.getString("reply"),
            rs.getString("reply_time"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public ReviewDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Review> listByStore(long storeId) {
        return jdbc.query("SELECT * FROM reviews WHERE store_id = ? ORDER BY id DESC", MAPPER, storeId);
    }

    public List<Review> listByGoods(long goodsId) {
        return jdbc.query("SELECT * FROM reviews WHERE goods_id = ? ORDER BY id DESC", MAPPER, goodsId);
    }

    public List<Review> listByStores(List<Long> storeIds) {
        if (storeIds == null || storeIds.isEmpty()) {
            return List.of();
        }
        String placeholders = storeIds.stream().map(s -> "?").collect(Collectors.joining(","));
        return jdbc.query("SELECT * FROM reviews WHERE store_id IN (" + placeholders + ") ORDER BY id DESC",
                MAPPER, storeIds.toArray());
    }

    public Optional<Review> findById(long id) {
        return jdbc.query("SELECT * FROM reviews WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    public long insert(long orderId, long storeId, long goodsId, long userId, String userName, int rating,
                       String content, String tagsJson, String imagesJson, int anonymous, String now) {
        jdbc.update("INSERT INTO reviews(order_id, store_id, goods_id, user_id, user_name, rating, content, tags, images, anonymous, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                orderId, storeId, goodsId, userId, userName, rating, content, tagsJson, imagesJson, anonymous, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public boolean existsByOrderGoods(long orderId, long goodsId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM reviews WHERE order_id = ? AND goods_id = ?",
                Integer.class, orderId, goodsId);
        return count != null && count > 0;
    }

    public long countByOrder(long orderId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(DISTINCT goods_id) FROM reviews WHERE order_id = ?",
                Integer.class, orderId);
        return count == null ? 0 : count;
    }

    public double avgRating(long storeId) {
        Double avg = jdbc.queryForObject("SELECT AVG(rating) FROM reviews WHERE store_id = ?", Double.class, storeId);
        return avg == null ? 0 : avg;
    }

    public double avgGoodsRating(long goodsId) {
        Double avg = jdbc.queryForObject("SELECT AVG(rating) FROM reviews WHERE goods_id = ?", Double.class, goodsId);
        return avg == null ? 0 : avg;
    }

    public void reply(long reviewId, String reply, String now) {
        jdbc.update("UPDATE reviews SET reply = ?, reply_time = ? WHERE id = ?", reply, now, reviewId);
    }
}
