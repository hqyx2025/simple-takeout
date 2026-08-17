package com.example.takeout.dao;

import com.example.takeout.model.AdminStatistics;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;

/** 平台统计查询，所有数据直接来自 MySQL，不引入缓存依赖。 */
@Repository
public class AdminStatsDao {
    private final JdbcTemplate jdbc;

    public AdminStatsDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public AdminStatistics overview(int hotLimit) {
        String sql = "SELECT " +
                "(SELECT COUNT(*) FROM users WHERE role = 0) AS total_users, " +
                "(SELECT COUNT(*) FROM users WHERE role = 1) AS total_merchants, " +
                "(SELECT COUNT(*) FROM stores) AS total_stores, " +
                "(SELECT COUNT(*) FROM goods) AS total_goods, " +
                "(SELECT COUNT(*) FROM orders) AS total_orders, " +
                "COALESCE((SELECT SUM(pay_amount) FROM orders WHERE status NOT IN (5,6)), 0) AS total_gmv, " +
                "COALESCE((SELECT SUM(pay_amount) FROM orders WHERE status = 4 AND escrow_status = 1), 0) AS settled_amount, " +
                "COALESCE((SELECT SUM(pay_amount) FROM orders WHERE status IN (1,2,3,4) AND escrow_status = 0), 0) AS pending_escrow_amount, " +
                "(SELECT COUNT(*) FROM orders WHERE LEFT(create_time, 10) = ?) AS today_orders, " +
                "COALESCE((SELECT SUM(pay_amount) FROM orders WHERE LEFT(create_time, 10) = ? AND status NOT IN (5,6)), 0) AS today_gmv";
        String today = LocalDate.now().toString();
        AdminStatistics base = jdbc.queryForObject(sql, (rs, rowNum) -> new AdminStatistics(
                rs.getLong("total_users"),
                rs.getLong("total_merchants"),
                rs.getLong("total_stores"),
                rs.getLong("total_goods"),
                rs.getLong("total_orders"),
                rs.getDouble("total_gmv"),
                rs.getDouble("settled_amount"),
                rs.getDouble("pending_escrow_amount"),
                rs.getLong("today_orders"),
                rs.getDouble("today_gmv"),
                List.of()
        ), today, today);
        List<AdminStatistics.HotGoods> hotGoods = jdbc.query(
                "SELECT g.id, g.name, g.store_id, s.name AS store_name, g.sales, g.price, g.status " +
                        "FROM goods g JOIN stores s ON s.id = g.store_id " +
                        "ORDER BY g.sales DESC, g.id DESC LIMIT ?",
                (rs, rowNum) -> new AdminStatistics.HotGoods(
                        rs.getLong("id"), rs.getString("name"), rs.getLong("store_id"),
                        rs.getString("store_name"), rs.getInt("sales"), rs.getDouble("price"),
                        rs.getInt("status")
                ), Math.max(1, Math.min(hotLimit, 50)));
        return new AdminStatistics(base.totalUsers(), base.totalMerchants(), base.totalStores(), base.totalGoods(),
                base.totalOrders(), base.totalGmv(), base.settledAmount(), base.pendingEscrowAmount(),
                base.todayOrders(), base.todayGmv(), hotGoods);
    }

    public List<AdminStatistics.TrendPoint> orderTrend(int days) {
        int safeDays = Math.max(1, Math.min(days, 90));
        LocalDate start = LocalDate.now().minusDays(safeDays - 1L);
        return jdbc.query(
                "SELECT LEFT(create_time, 10) AS order_date, COUNT(*) AS order_count, " +
                        "COALESCE(SUM(CASE WHEN status NOT IN (5,6) THEN pay_amount ELSE 0 END), 0) AS gmv " +
                        "FROM orders WHERE LEFT(create_time, 10) >= ? GROUP BY LEFT(create_time, 10) ORDER BY order_date",
                (rs, rowNum) -> new AdminStatistics.TrendPoint(rs.getString("order_date"),
                        rs.getLong("order_count"), rs.getDouble("gmv")), start.toString());
    }
}
