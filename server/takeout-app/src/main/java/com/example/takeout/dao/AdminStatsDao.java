package com.example.takeout.dao;

import com.example.takeout.model.AdminStatistics;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;

/** 平台统计使用支付与成功退款事实；累计下单数保留所有状态。 */
@Repository
public class AdminStatsDao {
    private static final String ORDER_PAY_TIME = JdbcDateTimes.value("o.pay_time");
    private static final String DAY_PARAMETER = "STR_TO_DATE(?, '%Y-%m-%d')";
    private static final String PAID_ORDER = "o.status IN (1,2,3,4,6) AND o.escrow_status <> 2 AND " + ORDER_PAY_TIME + " IS NOT NULL";
    private static final String NET_PAID = "GREATEST(o.pay_amount - COALESCE(refunds.refunded_amount, 0), 0)";
    private static final String ORDER_FACTS = " FROM orders o " + OrderDao.successfulRefundsJoin("o") +
            " LEFT JOIN order_settlements settlement ON settlement.order_id = o.id ";

    private final JdbcTemplate jdbc;

    public AdminStatsDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public AdminStatistics overview(int hotLimit) {
        String todayWindow = PAID_ORDER + " AND " + ORDER_PAY_TIME + " >= " + DAY_PARAMETER +
                " AND " + ORDER_PAY_TIME + " < " + DAY_PARAMETER;
        String sql = "SELECT " +
                "(SELECT COUNT(*) FROM users WHERE role = 0) AS total_users, " +
                "(SELECT COUNT(*) FROM users WHERE role = 1) AS total_merchants, " +
                "(SELECT COUNT(*) FROM stores) AS total_stores, " +
                "(SELECT COUNT(*) FROM goods) AS total_goods, " +
                "COUNT(*) AS total_orders, " +
                "COALESCE(SUM(CASE WHEN " + PAID_ORDER + " THEN " + NET_PAID + " ELSE 0 END), 0) AS total_gmv, " +
                "COALESCE(SUM(CASE WHEN " + OrderDao.wasSettled("o") + " THEN " + NET_PAID + " ELSE 0 END), 0) AS settled_amount, " +
                "COALESCE(SUM(CASE WHEN " + PAID_ORDER + " AND o.escrow_status = 0 THEN " + NET_PAID + " ELSE 0 END), 0) AS pending_escrow_amount, " +
                "COALESCE(SUM(CASE WHEN " + todayWindow + " THEN 1 ELSE 0 END), 0) AS today_orders, " +
                "COALESCE(SUM(CASE WHEN " + todayWindow + " THEN " + NET_PAID + " ELSE 0 END), 0) AS today_gmv" + ORDER_FACTS;
        LocalDate todayDate = LocalDate.now();
        String today = todayDate.toString();
        String tomorrow = todayDate.plusDays(1).toString();
        AdminStatistics base = jdbc.queryForObject(sql, (rs, rowNum) -> new AdminStatistics(
                rs.getLong("total_users"), rs.getLong("total_merchants"), rs.getLong("total_stores"),
                rs.getLong("total_goods"), rs.getLong("total_orders"), rs.getDouble("total_gmv"),
                rs.getDouble("settled_amount"), rs.getDouble("pending_escrow_amount"),
                rs.getLong("today_orders"), rs.getDouble("today_gmv"), List.of()
        ), today, tomorrow, today, tomorrow);
        List<AdminStatistics.HotGoods> hotGoods = jdbc.query(
                "SELECT g.id, g.name, g.store_id, s.name AS store_name, COALESCE(sold.sales, 0) AS sales, g.price, g.status " +
                        "FROM goods g JOIN stores s ON s.id = g.store_id " + GoodsDao.MONTHLY_SALES_JOIN +
                        "WHERE g.deleted = 0 ORDER BY sales DESC, g.id DESC LIMIT ?",
                (rs, rowNum) -> new AdminStatistics.HotGoods(
                        rs.getLong("id"), rs.getString("name"), rs.getLong("store_id"),
                        rs.getString("store_name"), rs.getInt("sales"), rs.getDouble("price"), rs.getInt("status")
                ), GoodsDao.monthlySalesArgs(Math.max(1, Math.min(hotLimit, 50))));
        return new AdminStatistics(base.totalUsers(), base.totalMerchants(), base.totalStores(), base.totalGoods(),
                base.totalOrders(), base.totalGmv(), base.settledAmount(), base.pendingEscrowAmount(),
                base.todayOrders(), base.todayGmv(), hotGoods);
    }

    public List<AdminStatistics.TrendPoint> orderTrend(int days) {
        int safeDays = Math.max(1, Math.min(days, 90));
        LocalDate today = LocalDate.now();
        LocalDate start = today.minusDays(safeDays - 1L);
        return jdbc.query(
                "SELECT DATE(" + ORDER_PAY_TIME + ") AS order_date, COUNT(*) AS order_count, " +
                        "COALESCE(SUM(" + NET_PAID + "), 0) AS gmv " + ORDER_FACTS +
                        "WHERE " + PAID_ORDER + " AND " + ORDER_PAY_TIME + " >= " + DAY_PARAMETER +
                        " AND " + ORDER_PAY_TIME + " < " + DAY_PARAMETER +
                        " GROUP BY DATE(" + ORDER_PAY_TIME + ") ORDER BY order_date",
                (rs, rowNum) -> new AdminStatistics.TrendPoint(rs.getString("order_date"),
                        rs.getLong("order_count"), rs.getDouble("gmv")), start.toString(), today.plusDays(1).toString());
    }

    /** 订单状态分布（含未支付、取消和售后状态）。 */
    public List<AdminStatistics.OrderStatusCount> orderStatusCounts() {
        return jdbc.query("SELECT status, COUNT(*) AS cnt FROM orders GROUP BY status ORDER BY status",
                (rs, rowNum) -> new AdminStatistics.OrderStatusCount(rs.getInt("status"), rs.getLong("cnt")));
    }

    /** 近30天店铺净成交额与支付订单数；部分退款保留订单数，全额退款排除。 */
    public List<AdminStatistics.TopStore> topStores(int limit) {
        return jdbc.query("SELECT s.id, s.name, COALESCE(sold.gmv, 0) AS gmv, COALESCE(sold.cnt, 0) AS cnt " +
                        "FROM stores s LEFT JOIN (SELECT o.store_id, SUM(" + NET_PAID + ") AS gmv, COUNT(*) AS cnt " +
                        ORDER_FACTS + "WHERE " + GoodsDao.recentPaidOrders("o") +
                        " GROUP BY o.store_id) sold ON sold.store_id = s.id " +
                        "ORDER BY gmv DESC, cnt DESC, s.id DESC LIMIT ?",
                (rs, rowNum) -> new AdminStatistics.TopStore(rs.getLong("id"), rs.getString("name"),
                        rs.getDouble("gmv"), rs.getLong("cnt")),
                GoodsDao.monthlySalesArgs(Math.max(1, Math.min(limit, 50))));
    }
}
