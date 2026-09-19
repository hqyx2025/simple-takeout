package com.example.takeout.dao;

import com.example.takeout.model.AdminStatistics;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;

/**
 * 平台统计查询，所有数据直接来自 MySQL，不引入缓存依赖。
 *
 * 口径：订单数与成交额必须**同时**排除已取消(5)与退款中(6)，否则同屏展示会自相矛盾
 * （历史缺陷：today_orders 含已取消订单、today_gmv 排除 5/6，于是"今日订单 10 / 今日成交 ¥0"
 * 看着像数据错了；近7日趋势的 order_count 也是同一个漏网字段）。
 * total_orders 是"累计下单数"的展示口径，故意含全部状态，不要一并改掉。
 */
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
                "(SELECT COUNT(*) FROM orders WHERE LEFT(create_time, 10) = ? AND status NOT IN (5,6)) AS today_orders, " +
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
                "SELECT LEFT(create_time, 10) AS order_date, " +
                        "COUNT(CASE WHEN status NOT IN (5,6) THEN 1 END) AS order_count, " +
                        "COALESCE(SUM(CASE WHEN status NOT IN (5,6) THEN pay_amount ELSE 0 END), 0) AS gmv " +
                        "FROM orders WHERE LEFT(create_time, 10) >= ? GROUP BY LEFT(create_time, 10) ORDER BY order_date",
                (rs, rowNum) -> new AdminStatistics.TrendPoint(rs.getString("order_date"),
                        rs.getLong("order_count"), rs.getDouble("gmv")), start.toString());
    }

    /** 订单状态分布（大屏饼图数据源）。 */
    public List<AdminStatistics.OrderStatusCount> orderStatusCounts() {
        return jdbc.query("SELECT status, COUNT(*) AS cnt FROM orders GROUP BY status ORDER BY status",
                (rs, rowNum) -> new AdminStatistics.OrderStatusCount(rs.getInt("status"), rs.getLong("cnt")));
    }

    /** 店铺成交额排行（大屏 Top 榜，排除取消 5/退款中 6，与平台统计口径一致）。 */
    public List<AdminStatistics.TopStore> topStores(int limit) {
        return jdbc.query("SELECT s.id, s.name, COALESCE(SUM(o.pay_amount), 0) AS gmv, COUNT(o.id) AS cnt " +
                        "FROM stores s LEFT JOIN orders o ON o.store_id = s.id AND o.status NOT IN (5,6) " +
                        "GROUP BY s.id, s.name ORDER BY gmv DESC, cnt DESC LIMIT ?",
                (rs, rowNum) -> new AdminStatistics.TopStore(rs.getLong("id"), rs.getString("name"),
                        rs.getDouble("gmv"), rs.getLong("cnt")),
                Math.max(1, Math.min(limit, 50)));
    }
}
