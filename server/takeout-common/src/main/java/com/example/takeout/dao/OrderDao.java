package com.example.takeout.dao;

import com.example.takeout.model.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.ArrayList;
import java.util.Map;
import java.util.Optional;

/**
 * 订单数据访问
 */
@Repository
public class OrderDao {

    private static final String DATE_PARAMETER = JdbcDateTimes.PARAMETER;

    private static final RowMapper<Order> MAPPER = (rs, i) -> new Order(
            rs.getLong("id"),
            rs.getString("order_no"),
            rs.getLong("user_id"),
            rs.getLong("store_id"),
            rs.getString("store_name"),
            rs.getInt("status"),
            rs.getString("items"),
            rs.getString("address"),
            rs.getDouble("goods_amount"),
            rs.getDouble("delivery_fee"),
            rs.getDouble("discount"),
            rs.getDouble("pay_amount"),
            rs.getString("remark"),
            rs.getInt("reviewed"),
            rs.getInt("escrow_status"),
            rs.getString("create_time"),
            rs.getString("pay_time"),
            rs.getString("accept_time"),
            rs.getString("deliver_time"),
            rs.getString("complete_time"),
            rs.getString("expect_time"),
            rs.getLong("coupon_id"),
            rs.getString("delivery_type")
    );

    private final JdbcTemplate jdbc;

    public OrderDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    private static String dateTimeExpression(String legacyColumn) {
        return JdbcDateTimes.value(legacyColumn);
    }

    private static String shadowTimeColumn(String legacyColumn) {
        return switch (legacyColumn) {
            case "create_time", "pay_time", "accept_time", "deliver_time", "complete_time", "ready_time",
                    "expect_time" -> legacyColumn + "_dt";
            default -> throw new IllegalArgumentException("Unsupported order time field");
        };
    }

    public long insert(Order o) {
        jdbc.update("INSERT INTO orders(order_no, user_id, store_id, store_name, status, items, address, goods_amount, delivery_fee, discount, coupon_id, pay_amount, remark, reviewed, escrow_status, create_time, pay_time, accept_time, deliver_time, complete_time, expect_time, create_time_dt, pay_time_dt, accept_time_dt, deliver_time_dt, complete_time_dt, expect_time_dt, delivery_type) " +
                        "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,? ," + DATE_PARAMETER + "," + DATE_PARAMETER + "," +
                        DATE_PARAMETER + "," + DATE_PARAMETER + "," + DATE_PARAMETER + "," + DATE_PARAMETER + ",?)",
                o.orderNo(), o.userId(), o.storeId(), o.storeName(), o.status(), o.items(), o.address(),
                o.goodsAmount(), o.deliveryFee(), o.discount(), o.couponId(), o.payAmount(), o.remark(),
                o.reviewed(), 0, o.createTime(), o.payTime(), o.acceptTime(), o.deliverTime(),
                o.completeTime(), o.expectTime(), o.createTime(), o.payTime(), o.acceptTime(), o.deliverTime(),
                o.completeTime(), o.expectTime(), o.deliveryType());
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    /** 新订单同时写入规范化商品快照；调用方在创建订单事务内执行。 */
    public void insertItems(long orderId, List<Order.OrderItem> items) {
        if (items == null || items.isEmpty()) {
            return;
        }
        String sql = "INSERT INTO order_items(order_id, line_no, goods_id, goods_name, unit_price, quantity, " +
                "image, spec_id, spec_name, seckill_id) VALUES(?,?,?,?,?,?,?,?,?,?)";
        for (int i = 0; i < items.size(); i++) {
            Order.OrderItem item = items.get(i);
            jdbc.update(sql, orderId, i + 1, item.goodsId(), item.goodsName(), item.price(), item.quantity(),
                    item.image(), item.specId(), item.specName(), item.seckillId());
        }
    }

    /** 用户是否已有任何订单（新客立减判断：从未下单才享新客优惠）。 */
    public boolean hasAnyOrder(long userId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM orders WHERE user_id = ?", Integer.class, userId);
        return count != null && count > 0;
    }

    public List<Order> listByUser(long userId) {
        return jdbc.query("SELECT * FROM orders WHERE user_id = ? ORDER BY id DESC", MAPPER, userId);
    }

    public int countByUser(long userId, Integer status) {
        String sql = status == null ? "SELECT COUNT(*) FROM orders WHERE user_id = ?"
                : "SELECT COUNT(*) FROM orders WHERE user_id = ? AND status = ?";
        Integer count = status == null ? jdbc.queryForObject(sql, Integer.class, userId)
                : jdbc.queryForObject(sql, Integer.class, userId, status);
        return count == null ? 0 : count;
    }

    public List<Order> listByUser(long userId, Integer status, int pageSize, long offset) {
        String sql = status == null
                ? "SELECT * FROM orders WHERE user_id = ? ORDER BY id DESC LIMIT ? OFFSET ?"
                : "SELECT * FROM orders WHERE user_id = ? AND status = ? ORDER BY id DESC LIMIT ? OFFSET ?";
        return status == null
                ? jdbc.query(sql, MAPPER, userId, pageSize, offset)
                : jdbc.query(sql, MAPPER, userId, status, pageSize, offset);
    }

    public List<Order> listByStore(long storeId) {
        return jdbc.query("SELECT * FROM orders WHERE store_id = ? ORDER BY id DESC", MAPPER, storeId);
    }

    public int countByMerchant(long ownerId, Integer status) {
        String sql = "SELECT COUNT(*) FROM orders o JOIN stores s ON s.id = o.store_id " +
                "WHERE s.owner_id = ? AND o.status <> 0" + (status == null ? "" : " AND o.status = ?");
        Integer count = status == null ? jdbc.queryForObject(sql, Integer.class, ownerId)
                : jdbc.queryForObject(sql, Integer.class, ownerId, status);
        return count == null ? 0 : count;
    }

    public List<AdminOrderRow> listByMerchant(long ownerId, Integer status, int pageSize, long offset) {
        String sql = "SELECT o.*, COALESCE(r.name, '') AS rider_name, COALESCE(r.phone, '') AS rider_phone " +
                "FROM orders o JOIN stores s ON s.id = o.store_id LEFT JOIN riders r ON r.id = o.rider_id " +
                "WHERE s.owner_id = ? AND o.status <> 0" + (status == null ? "" : " AND o.status = ?") +
                " ORDER BY o.id DESC LIMIT ? OFFSET ?";
        org.springframework.jdbc.core.RowMapper<AdminOrderRow> mapper = (rs, rowNum) ->
                new AdminOrderRow(MAPPER.mapRow(rs, rowNum), rs.getString("rider_name"),
                        rs.getString("rider_phone"), rs.getString("ready_time"));
        return status == null
                ? jdbc.query(sql, mapper, ownerId, pageSize, offset)
                : jdbc.query(sql, mapper, ownerId, status, pageSize, offset);
    }

    public List<Order> listAll() {
        return jdbc.query("SELECT * FROM orders ORDER BY id DESC", MAPPER);
    }

    public int countForAdmin(Integer status) {
        String sql = status == null ? "SELECT COUNT(*) FROM orders" : "SELECT COUNT(*) FROM orders WHERE status = ?";
        Integer count = status == null ? jdbc.queryForObject(sql, Integer.class)
                : jdbc.queryForObject(sql, Integer.class, status);
        return count == null ? 0 : count;
    }

    public List<Order> listForAdmin(Integer status, int pageSize, long offset) {
        String sql = status == null
                ? "SELECT * FROM orders ORDER BY id DESC LIMIT ? OFFSET ?"
                : "SELECT * FROM orders WHERE status = ? ORDER BY id DESC LIMIT ? OFFSET ?";
        return status == null
                ? jdbc.query(sql, MAPPER, pageSize, offset)
                : jdbc.query(sql, MAPPER, status, pageSize, offset);
    }

    public List<AdminOrderRow> listForAdminWithRider(Integer status, int pageSize, long offset) {
        String sql = "SELECT o.*, COALESCE(r.name, '') AS rider_name, COALESCE(r.phone, '') AS rider_phone " +
                "FROM orders o LEFT JOIN riders r ON r.id = o.rider_id " +
                (status == null ? "" : "WHERE o.status = ? ") + "ORDER BY o.id DESC LIMIT ? OFFSET ?";
        org.springframework.jdbc.core.RowMapper<AdminOrderRow> mapper = (rs, rowNum) ->
                new AdminOrderRow(MAPPER.mapRow(rs, rowNum), rs.getString("rider_name"),
                        rs.getString("rider_phone"), rs.getString("ready_time"));
        return status == null
                ? jdbc.query(sql, mapper, pageSize, offset)
                : jdbc.query(sql, mapper, status, pageSize, offset);
    }

    public record AdminOrderRow(Order order, String riderName, String riderPhone, String readyTime) {
    }

    public Optional<Order> findById(long id) {
        return jdbc.query("SELECT * FROM orders WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    /**
     * 条件状态流转（状态机唯一入口）：仅当当前状态等于 fromStatus 时更新，返回 false 表示
     * 状态已被其它操作改变（用户取消 / 骑手接单 / 并发流转），调用方必须回滚整单并提示刷新。
     * timeField 只允许传常量列名（内部调用，不接受外部输入）。
     */
    public boolean updateStatusFrom(long id, int fromStatus, int toStatus, String timeField, String timeValue) {
        String shadowColumn = shadowTimeColumn(timeField);
        return jdbc.update("UPDATE orders SET status = ?, " + timeField + " = ?, " + shadowColumn + " = " +
                        DATE_PARAMETER + " WHERE id = ? AND status = ?",
                toStatus, timeValue, timeValue, id, fromStatus) == 1;
    }

    /** 条件状态流转（不写时间字段），用于退款申请/审批回退等无时间语义的流转。 */
    public boolean updateStatusOnlyFrom(long id, int fromStatus, int toStatus) {
        return jdbc.update("UPDATE orders SET status = ? WHERE id = ? AND status = ?", toStatus, id, fromStatus) == 1;
    }

    /** 申请退款：4 已送达 + escrow 0 托管中 → 6 退款中（条件更新，防与确认收货/重复申请并发）。 */
    public boolean markRefunding(long id) {
        return jdbc.update("UPDATE orders SET status = 6 WHERE id = ? AND status = 4 AND escrow_status = 0", id) == 1;
    }

    /** 商户自行配送：2 → 3（条件更新同时锁 rider_id，防与骑手抢单并发）。 */
    public boolean merchantDeliver(long id, String now) {
        return jdbc.update("UPDATE orders SET status = 3, deliver_time = ?, deliver_time_dt = " + DATE_PARAMETER +
                        " WHERE id = ? AND status = 2 AND rider_id = 0",
                now, now, id) == 1;
    }

    /** 商户确认送达：3 → 4（仅未分配骑手的订单）。 */
    public boolean merchantComplete(long id, String now) {
        return jdbc.update("UPDATE orders SET status = 4, complete_time = ?, complete_time_dt = " + DATE_PARAMETER +
                        " WHERE id = ? AND status = 3 AND rider_id = 0",
                now, now, id) == 1;
    }

    // ============ 待付款支付模型 ============

    /** 支付成功：0 待付款 → 1 待接单（条件更新，防重复支付）。 */
    public boolean markPaid(long id, String payTime) {
        return jdbc.update("UPDATE orders SET status = 1, pay_time = ?, pay_time_dt = " + DATE_PARAMETER +
                        " WHERE id = ? AND status = 0",
                payTime, payTime, id) == 1;
    }

    public Optional<Order> findByIdForUpdate(long id) {
        return jdbc.query("SELECT * FROM orders WHERE id = ? FOR UPDATE", MAPPER, id).stream().findFirst();
    }

    /**
     * 待付款超时订单；legacy-only rows are parsed explicitly instead of relying on VARCHAR coercion.
     * ponytail: 单轮固定上限 500 条，避免极端积压时一次把全表待付款订单读进内存；
     * 剩余订单等下一轮扫描处理（取消是条件更新，天然幂等）。量级远超此值再改 id 游标分页。
     */
    public List<Order> listExpiredPending(String deadline) {
        return jdbc.query("SELECT * FROM orders WHERE status = 0 AND " + dateTimeExpression("create_time") +
                        " < " + DATE_PARAMETER + " ORDER BY id LIMIT 500",
                MAPPER, deadline);
    }

    /** 取消待付款订单：0 → 5（条件更新，防止与用户手动支付/取消并发冲突）。 */
    public boolean cancelPending(long id, String now) {
        return jdbc.update("UPDATE orders SET status = 5, complete_time = ?, complete_time_dt = " + DATE_PARAMETER +
                        " WHERE id = ? AND status = 0",
                now, now, id) == 1;
    }

    public void markReviewed(long id) {
        jdbc.update("UPDATE orders SET reviewed = 1 WHERE id = ?", id);
    }

    /** 将托管款标记为已退款，条件更新避免重复退款。 */
    public boolean refundEscrow(long id) {
        return jdbc.update("UPDATE orders SET escrow_status = 2 WHERE id = ? AND escrow_status = 0", id) == 1;
    }

    /** 将托管款标记为已结算，条件更新避免重复给商户打款。 */
    public boolean releaseEscrow(long id) {
        return jdbc.update("UPDATE orders SET escrow_status = 1 WHERE id = ? AND escrow_status = 0", id) == 1;
    }

    public List<Order> listSettledByStore(long storeId) {
        return jdbc.query("SELECT * FROM orders WHERE store_id = ? AND status = 4 AND escrow_status = 1 ORDER BY id DESC",
                MAPPER, storeId);
    }

    /**
     * 商户统计聚合。统计页只需要计数和金额，避免把商户历史订单全部读入应用内存。
     * Shadows are used only when they still match the legacy values during a rolling upgrade.
     */
    public MerchantStatsAggregate aggregateMerchantStats(long storeId, String todayStart, String tomorrowStart,
                                                          String weekStart, String monthStart,
                                                          List<String> dayStarts) {
        if (dayStarts == null || dayStarts.size() != 7) {
            throw new IllegalArgumentException("dayStarts must contain 7 dates");
        }
        StringBuilder sql = new StringBuilder("SELECT ");
        List<Object> args = new ArrayList<>();
        appendCount(sql, args, "today_orders", "status <> 0 AND " + dateTimeExpression("create_time") + " >= " + DATE_PARAMETER +
                " AND " + dateTimeExpression("create_time") + " < " + DATE_PARAMETER, todayStart, tomorrowStart);
        appendAmount(sql, args, "today_income", "status = 4 AND escrow_status = 1 AND " + dateTimeExpression("complete_time") +
                " >= " + DATE_PARAMETER + " AND " + dateTimeExpression("complete_time") + " < " + DATE_PARAMETER,
                todayStart, tomorrowStart);
        appendCount(sql, args, "today_completed", "status = 4 AND escrow_status = 1 AND " + dateTimeExpression("complete_time") +
                " >= " + DATE_PARAMETER + " AND " + dateTimeExpression("complete_time") + " < " + DATE_PARAMETER,
                todayStart, tomorrowStart);
        appendCount(sql, args, "week_orders", "status <> 0 AND " + dateTimeExpression("create_time") + " >= " + DATE_PARAMETER,
                weekStart);
        appendAmount(sql, args, "week_income", "status = 4 AND escrow_status = 1 AND " + dateTimeExpression("complete_time") +
                " >= " + DATE_PARAMETER, weekStart);
        appendCount(sql, args, "week_completed", "status = 4 AND escrow_status = 1 AND " + dateTimeExpression("complete_time") +
                " >= " + DATE_PARAMETER, weekStart);
        appendCount(sql, args, "month_orders", "status <> 0 AND " + dateTimeExpression("create_time") + " >= " + DATE_PARAMETER,
                monthStart);
        appendAmount(sql, args, "month_income", "status = 4 AND escrow_status = 1 AND " + dateTimeExpression("complete_time") +
                " >= " + DATE_PARAMETER, monthStart);
        appendCount(sql, args, "month_completed", "status = 4 AND escrow_status = 1 AND " + dateTimeExpression("complete_time") +
                " >= " + DATE_PARAMETER, monthStart);
        appendCount(sql, args, "total_orders", "status <> 0");
        appendAmount(sql, args, "total_income", "status = 4 AND escrow_status = 1");
        for (int i = 0; i < 7; i++) {
            String end = i == 6 ? tomorrowStart : dayStarts.get(i + 1);
            appendAmount(sql, args, "day_income_" + i,
                    "status = 4 AND escrow_status = 1 AND " + dateTimeExpression("complete_time") + " >= " + DATE_PARAMETER +
                            " AND " + dateTimeExpression("complete_time") + " < " + DATE_PARAMETER,
                    dayStarts.get(i), end);
        }
        for (int status = 1; status <= 5; status++) {
            appendCount(sql, args, "status_" + status,
                    "status = " + status + " AND " + dateTimeExpression("create_time") + " >= " + DATE_PARAMETER + " AND " +
                            dateTimeExpression("create_time") + " < " + DATE_PARAMETER, todayStart, tomorrowStart);
        }
        sql.append(" FROM orders WHERE store_id = ?");
        args.add(storeId);
        Map<String, Object> row = jdbc.queryForMap(sql.toString(), args.toArray());
        return MerchantStatsAggregate.from(row);
    }

    private static void appendCount(StringBuilder sql, List<Object> args, String alias, String condition,
                                    Object... values) {
        appendComma(sql);
        sql.append("SUM(CASE WHEN ").append(condition).append(" THEN 1 ELSE 0 END) AS ").append(alias);
        for (Object value : values) args.add(value);
    }

    private static void appendAmount(StringBuilder sql, List<Object> args, String alias, String condition,
                                     Object... values) {
        appendComma(sql);
        sql.append("COALESCE(SUM(CASE WHEN ").append(condition).append(" THEN pay_amount ELSE 0 END), 0) AS ").append(alias);
        for (Object value : values) args.add(value);
    }

    private static void appendComma(StringBuilder sql) {
        if (sql.charAt(sql.length() - 1) != ' ') sql.append(", ");
    }

    public record MerchantStatsAggregate(long todayOrders, double todayIncome, long todayCompleted,
                                         long weekOrders, double weekIncome, long weekCompleted,
                                         long monthOrders, double monthIncome, long monthCompleted,
                                         long totalOrders, double totalIncome, List<Double> dayIncome,
                                         List<Long> statusCounts) {
        private static MerchantStatsAggregate from(Map<String, Object> row) {
            List<Double> days = new ArrayList<>();
            for (int i = 0; i < 7; i++) days.add(number(row.get("day_income_" + i)).doubleValue());
            List<Long> statuses = new ArrayList<>();
            for (int i = 1; i <= 5; i++) statuses.add(number(row.get("status_" + i)).longValue());
            return new MerchantStatsAggregate(
                    number(row.get("today_orders")).longValue(), number(row.get("today_income")).doubleValue(),
                    number(row.get("today_completed")).longValue(), number(row.get("week_orders")).longValue(),
                    number(row.get("week_income")).doubleValue(), number(row.get("week_completed")).longValue(),
                    number(row.get("month_orders")).longValue(), number(row.get("month_income")).doubleValue(),
                    number(row.get("month_completed")).longValue(), number(row.get("total_orders")).longValue(),
                    number(row.get("total_income")).doubleValue(),
                    List.copyOf(days), List.copyOf(statuses));
        }

        private static Number number(Object value) {
            return value instanceof Number n ? n : 0;
        }
    }

    // ============ 四端改造：骑手配送 ============

    /** 商户出餐完成：写 ready_time，订单进入待取餐池（幂等，重复调用不覆盖）。 */
    public boolean markReady(long id, String now) {
        return jdbc.update("UPDATE orders SET ready_time = ?, ready_time_dt = " + DATE_PARAMETER +
                        " WHERE id = ? AND status = 2 AND ready_time = ''",
                now, now, id) == 1;
    }

    /** 待取餐池：已出餐但尚未分配骑手。 */
    public List<Order> listRiderPool() {
        return jdbc.query("SELECT * FROM orders WHERE status = 2 AND ready_time <> '' " +
                        "AND rider_id = 0 ORDER BY " + dateTimeExpression("ready_time"),
                MAPPER);
    }

    /** 骑手抢单：条件更新，防并发重复抢单（失败=已被他人抢走）。 */
    public boolean tryAssignRider(long id, long riderId) {
        return jdbc.update("UPDATE orders SET rider_id = ? WHERE id = ? AND rider_id = 0 AND status = 2 " +
                        "AND ready_time <> ''",
                riderId, id) == 1;
    }

    /** 骑手取餐：2 → 3（仅本人接的订单）。 */
    public boolean riderPickup(long id, long riderId, String now) {
        return jdbc.update("UPDATE orders SET status = 3, deliver_time = ?, deliver_time_dt = " + DATE_PARAMETER +
                        " WHERE id = ? AND rider_id = ? AND status = 2",
                now, now, id, riderId) == 1;
    }

    /** 骑手送达：3 → 4（仅本人接的订单）。 */
    public boolean riderDeliver(long id, long riderId, String now) {
        return jdbc.update("UPDATE orders SET status = 4, complete_time = ?, complete_time_dt = " + DATE_PARAMETER +
                        " WHERE id = ? AND rider_id = ? AND status = 3",
                now, now, id, riderId) == 1;
    }

    public List<Order> listByRider(long riderId) {
        return jdbc.query("SELECT * FROM orders WHERE rider_id = ? ORDER BY id DESC", MAPPER, riderId);
    }

    public int countByRider(long riderId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM orders WHERE rider_id = ?", Integer.class, riderId);
        return count == null ? 0 : count;
    }

    public List<Order> listByRider(long riderId, int pageSize, long offset) {
        return jdbc.query("SELECT * FROM orders WHERE rider_id = ? " +
                        "ORDER BY CASE WHEN status IN (2,3) THEN 0 ELSE 1 END, " +
                        "CASE WHEN status IN (2,3) THEN " + dateTimeExpression("ready_time") + " END ASC, " +
                        "CASE WHEN status NOT IN (2,3) THEN " + dateTimeExpression("complete_time") +
                        " END DESC, id DESC LIMIT ? OFFSET ?",
                MAPPER, riderId, pageSize, offset);
    }

    public long findRiderId(long orderId) {
        Long riderId = jdbc.queryForObject("SELECT rider_id FROM orders WHERE id = ?", Long.class, orderId);
        return riderId == null ? 0 : riderId;
    }

    /** 商户出餐时间：非空表示订单已出餐并在骑手待取餐池中（前端据此显示"已出餐，等待骑手接单"）。 */
    public String findReadyTime(long orderId) {
        String readyTime = jdbc.queryForObject("SELECT ready_time FROM orders WHERE id = ?", String.class, orderId);
        return readyTime == null ? "" : readyTime;
    }
}
