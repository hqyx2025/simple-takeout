package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.CouponDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.ReviewDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Address;
import com.example.takeout.model.Coupon;
import com.example.takeout.model.Goods;
import com.example.takeout.model.Order;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.model.Review;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

/**
 * 订单服务：下单、状态流转（接单→制作→配送→完成）、评价、商户统计
 * 状态码与客户端对齐：0待付款 1待接单 2制作中 3配送中 4已完成 5已取消 6退款中
 */
@Service
public class OrderService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final OrderDao orderDao;
    private final StoreDao storeDao;
    private final GoodsDao goodsDao;
    private final AddressDao addressDao;
    private final CouponDao couponDao;
    private final ReviewDao reviewDao;
    private final UserDao userDao;
    private final RefundDao refundDao;
    private final ObjectMapper objectMapper;

    public OrderService(OrderDao orderDao, StoreDao storeDao, GoodsDao goodsDao, AddressDao addressDao,
                        CouponDao couponDao, ReviewDao reviewDao, UserDao userDao, RefundDao refundDao,
                        ObjectMapper objectMapper) {
        this.orderDao = orderDao;
        this.storeDao = storeDao;
        this.goodsDao = goodsDao;
        this.addressDao = addressDao;
        this.couponDao = couponDao;
        this.reviewDao = reviewDao;
        this.userDao = userDao;
        this.refundDao = refundDao;
        this.objectMapper = objectMapper;
    }

    /** 创建订单：从用户余额扣款后进入平台托管，状态=1 待接单。 */
    @Transactional
    public Order.OrderView createOrder(long userId, long storeId, List<Order.OrderItem> items,
                                       long addressId, long couponId, String remark) {
        if (items == null || items.isEmpty()) {
            throw new BizException("订单商品不能为空");
        }
        Store store = storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        if (store.status() != 1) {
            throw new BizException("店铺当前未营业");
        }
        Address address = addressDao.listByUser(userId).stream()
                .filter(a -> a.id() == addressId)
                .findFirst()
                .orElseThrow(() -> new BizException("收货地址不存在"));

        // 金额计算：商品总价 + 配送费 - 优惠
        double goodsAmount = 0;
        List<Order.OrderItem> normalizedItems = new ArrayList<>();
        for (Order.OrderItem item : items) {
            if (item == null || item.quantity() <= 0) {
                throw new BizException("商品数量必须大于 0");
            }
            Goods goods = goodsDao.findById(item.goodsId())
                    .orElseThrow(() -> new BizException("商品不存在：" + item.goodsName()));
            if (goods.storeId() != storeId) {
                throw new BizException("订单包含其他店铺商品");
            }
            if (goods.status() != 1) {
                throw new BizException("商品已下架：" + goods.name());
            }
            if (goods.stock() < item.quantity()) {
                throw new BizException("「" + goods.name() + "」库存不足，仅剩 " + goods.stock() + " 件");
            }
            goodsAmount += goods.price() * item.quantity();
            normalizedItems.add(new Order.OrderItem(goods.id(), goods.name(), goods.price(), item.quantity(), goods.image()));
        }
        goodsAmount = round2(goodsAmount);
        if (goodsAmount < store.minOrder()) {
            throw new BizException("未达到店铺起送价（满" + (long) store.minOrder() + "元起送）");
        }
        double discount = 0;
        Coupon appliedCoupon = null;
        if (couponId > 0) {
            Coupon coupon = couponDao.listByUser(userId).stream()
                    .filter(c -> c.id() == couponId && c.status() == 0)
                    .findFirst()
                    .orElseThrow(() -> new BizException("优惠券不可用"));
            if (coupon.storeId() != 0 && coupon.storeId() != storeId) {
                throw new BizException("该优惠券不适用于当前店铺");
            }
            if (isExpired(coupon.expireTime())) {
                throw new BizException("优惠券已过期");
            }
            if (goodsAmount < coupon.threshold()) {
                throw new BizException("未达到优惠券使用门槛（满" + (long) coupon.threshold() + "元可用）");
            }
            discount = coupon.amount();
            appliedCoupon = coupon;
        }
        double payAmount = round2(goodsAmount + store.deliveryFee() - discount);
        if (payAmount < 0) {
            throw new BizException("优惠金额不能超过订单金额");
        }

        // 余额支付并进入平台托管；商户在用户确认收货前不能收到这笔钱。
        User user = userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在"));
        if (user.balance() < payAmount) {
            throw new BizException("余额不足，请先充值");
        }
        userDao.updateBalance(userId, round2(user.balance() - payAmount));
        if (appliedCoupon != null) {
            couponDao.markUsed(appliedCoupon.id());
        }
        // 扣减库存（乐观锁条件更新，防超卖）；任一失败整体回滚事务
        for (Order.OrderItem normalized : normalizedItems) {
            if (!goodsDao.deductStock(normalized.goodsId(), normalized.quantity())) {
                throw new BizException("「" + normalized.goodsName() + "」库存不足，请减少数量或联系商家");
            }
        }

        String now = LocalDateTime.now().format(FMT);
        String orderNo = genOrderNo();
        Order order = new Order(0, orderNo, userId, storeId, store.name(), 1,
                toJson(normalizedItems), toJson(new Order.AddressInfo(address.id(), address.name(), address.phone(), address.detail())),
                goodsAmount, store.deliveryFee(), discount, payAmount,
                remark == null ? "" : remark, 0, 0, now, now, "", "", "");
        long id = orderDao.insert(order);
        storeDao.updateMonthlySales(storeId, 1);
        return orderDetail(id);
    }

    public List<Order.OrderView> userOrders(long userId) {
        return orderDao.listByUser(userId).stream().map(this::toView).toList();
    }

    /**
     * 商户订单：仅可见自己店铺的订单
     */
    public List<Order.OrderView> merchantOrders(long ownerId) {
        List<Store> stores = storeDao.listByOwner(ownerId);
        List<Long> storeIds = stores.stream().map(Store::id).toList();
        if (storeIds.isEmpty()) {
            return List.of();
        }
        return storeIds.stream()
                .flatMap(sid -> orderDao.listByStore(sid).stream())
                .sorted((a, b) -> Long.compare(b.id(), a.id()))
                .map(this::toView)
                .toList();
    }

    public Order.OrderView orderDetail(long id) {
        Order order = orderDao.findById(id).orElseThrow(() -> new BizException("订单不存在"));
        return toView(order);
    }

    public Order.OrderView orderDetail(long requesterId, int role, long id) {
        Order order = requireOrder(id);
        if (order.userId() != requesterId && (role != 1 || !isStoreOwner(requesterId, order.storeId()))) {
            throw new BizException(403, "无权查看该订单");
        }
        return toView(order);
    }

    // ============ 状态流转 ============

    @Transactional
    public Order.OrderView cancelOrder(long userId, long orderId) {
        Order order = requireOrder(orderId);
        if (order.userId() != userId) {
            throw new BizException(403, "无权操作该订单");
        }
        if (order.status() != 1 && order.status() != 2 && order.status() != 3) {
            throw new BizException("当前状态不可取消");
        }
        // 仅在托管状态下退款，条件更新避免重复退回余额。
        if (!orderDao.refundEscrow(orderId)) {
            throw new BizException("订单资金已处理，不能重复退款");
        }
        // escrow 条件更新成功才回滚库存（同一事务内，防重复回滚）
        rollbackStock(order);
        User user = userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在"));
        userDao.updateBalance(userId, round2(user.balance() + order.payAmount()));
        orderDao.updateStatus(orderId, 5, "complete_time", LocalDateTime.now().format(FMT));
        return orderDetail(orderId);
    }

    /**
     * 用户申请退款（演进项：退款审批流程，见大纲 7.11/9.7/10.7）
     * 条件：订单已送达（status=4）、托管未结算（escrow=0）、未评价；申请后订单进入退款中（status=6）。
     */
    @Transactional
    public RefundRecord applyRefund(long userId, long orderId, String reason) {
        Order order = requireOrder(orderId);
        if (order.userId() != userId) {
            throw new BizException(403, "无权操作该订单");
        }
        if (order.status() != 4) {
            throw new BizException("仅已送达订单可申请退款");
        }
        if (order.escrowStatus() != 0) {
            throw new BizException("订单已结算或已退款，不能申请退款");
        }
        if (order.reviewed() == 1) {
            throw new BizException("订单已评价，不能申请退款");
        }
        if (refundDao.existsPending(orderId)) {
            throw new BizException("该订单已有进行中的退款申请，请等待审核");
        }
        Store store = storeDao.findById(order.storeId()).orElseThrow(() -> new BizException("店铺不存在"));
        String now = LocalDateTime.now().format(FMT);
        long id = refundDao.insert(orderId, userId, store.ownerId(),
                reason == null ? "" : reason, order.payAmount(), now);
        orderDao.updateStatusOnly(orderId, 6);
        return refundDao.findById(id).orElseThrow(() -> new BizException("退款申请失败"));
    }

    /** 回滚订单商品库存（取消/退款时调用，必须处于 escrow 条件更新成功后的同一事务内）。 */
    private void rollbackStock(Order order) {
        for (Order.OrderItem item : parseItems(order.items())) {
            goodsDao.restoreStock(item.goodsId(), item.quantity());
        }
    }

    public Order.OrderView merchantFlow(long ownerId, long orderId, String action) {
        Order order = requireOrder(orderId);
        Store store = storeDao.findById(order.storeId()).orElseThrow(() -> new BizException("店铺不存在"));
        if (store.ownerId() != ownerId) {
            throw new BizException(403, "无权操作该订单");
        }
        String now = LocalDateTime.now().format(FMT);
        switch (action) {
            case "accept" -> {          // 商户接单：1 → 2
                requireStatus(order, 1);
                orderDao.updateStatus(orderId, 2, "accept_time", now);
            }
            case "deliver" -> {         // 出餐配送：2 → 3
                requireStatus(order, 2);
                orderDao.updateStatus(orderId, 3, "deliver_time", now);
            }
            case "complete" -> {        // 确认送达：3 → 4
                requireStatus(order, 3);
                orderDao.updateStatus(orderId, 4, "complete_time", now);
            }
            default -> throw new BizException("不支持的操作：" + action);
        }
        return orderDetail(orderId);
    }

    @Transactional
    public Order.OrderView confirmOrder(long userId, long orderId) {
        Order order = requireOrder(orderId);
        if (order.userId() != userId) {
            throw new BizException(403, "无权操作该订单");
        }
        if (order.status() != 4) {
            throw new BizException("订单尚未完成，不能确认收货");
        }
        Store store = storeDao.findById(order.storeId()).orElseThrow(() -> new BizException("店铺不存在"));
        if (!orderDao.releaseEscrow(orderId)) {
            throw new BizException("订单款项已结算或退款，不能重复确认");
        }
        User merchant = userDao.findById(store.ownerId()).orElseThrow(() -> new BizException("商户不存在"));
        userDao.updateBalance(merchant.id(), round2(merchant.balance() + order.payAmount()));
        return orderDetail(orderId);
    }

    /**
     * 评价已完成订单
     */
    @Transactional
    public Review reviewOrder(long userId, long orderId, int rating, String content, List<String> tags) {
        return reviewOrder(userId, orderId, 0, rating, content, tags);
    }

    /** 评价已完成订单中的一个具体商品。一个订单仍保持一次评价幂等口径。 */
    @Transactional
    public Review reviewOrder(long userId, long orderId, long goodsId, int rating, String content, List<String> tags) {
        Order order = requireOrder(orderId);
        if (order.userId() != userId) {
            throw new BizException(403, "无权评价该订单");
        }
        if (order.status() != 4 || order.escrowStatus() != 1) {
            throw new BizException("确认收货并结算后才能评价商品");
        }
        if (order.reviewed() == 1) {
            throw new BizException("该订单已评价");
        }
        User user = userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在"));
        if (rating < 1 || rating > 5) {
            throw new BizException("评分范围 1-5");
        }
        List<Order.OrderItem> orderItems = parseItems(order.items());
        long targetGoodsId = goodsId;
        if (targetGoodsId <= 0 && !orderItems.isEmpty()) {
            targetGoodsId = orderItems.get(0).goodsId();
        }
        final long selectedGoodsId = targetGoodsId;
        Order.OrderItem targetItem = orderItems.stream()
                .filter(item -> item.goodsId() == selectedGoodsId)
                .findFirst()
                .orElseThrow(() -> new BizException("评价商品不在该订单中"));
        String now = LocalDateTime.now().format(FMT);
        long reviewId = reviewDao.insert(order.storeId(), targetItem.goodsId(), userId, user.username(),
                rating, content == null ? "" : content, toJson(tags == null ? List.of() : tags), now);
        orderDao.markReviewed(orderId);
        return reviewDao.listByStore(order.storeId()).stream()
                .filter(r -> r.id() == reviewId)
                .findFirst()
                .orElseThrow(() -> new BizException("评价失败"));
    }

    // ============ 商户统计 ============

    public MerchantStats merchantStats(long ownerId, long storeId, String range) {
        List<Store> stores = storeDao.listByOwner(ownerId);
        if (stores.isEmpty()) {
            return new MerchantStats(0, 0, 0, 0, 0, 0);
        }
        long sid = storeId > 0 ? storeId : stores.get(0).id();
        boolean owned = stores.stream().anyMatch(s -> s.id() == sid);
        if (!owned) {
            throw new BizException(403, "无权查看该店铺统计");
        }
        List<Order> orders = orderDao.listSettledByStore(sid);
        LocalDate today = LocalDate.now();
        LocalDate weekStart = today.minusDays(today.getDayOfWeek().getValue() - 1);
        LocalDate monthStart = today.withDayOfMonth(1);

        double todayIncome = sumSince(orders, today.atStartOfDay());
        double weekIncome = sumSince(orders, weekStart.atStartOfDay());
        double monthIncome = sumSince(orders, monthStart.atStartOfDay());
        long todayCount = countSince(orders, today.atStartOfDay());
        long weekCount = countSince(orders, weekStart.atStartOfDay());
        long monthCount = countSince(orders, monthStart.atStartOfDay());
        return new MerchantStats(todayCount, todayIncome, weekCount, weekIncome, monthCount, monthIncome);
    }

    private double sumSince(List<Order> orders, LocalDateTime since) {
        return orders.stream()
                .filter(o -> parseTime(o.completeTime()).isAfter(since.minusSeconds(1)))
                .mapToDouble(Order::payAmount)
                .sum();
    }

    private long countSince(List<Order> orders, LocalDateTime since) {
        return orders.stream()
                .filter(o -> parseTime(o.completeTime()).isAfter(since.minusSeconds(1)))
                .count();
    }

    private LocalDateTime parseTime(String time) {
        try {
            return LocalDateTime.parse(time, FMT);
        } catch (Exception e) {
            return LocalDateTime.MIN;
        }
    }

    public record MerchantStats(long todayCount, double todayIncome, long weekCount, double weekIncome,
                                long monthCount, double monthIncome) {
    }

    // ============ 工具 ============

    private Order requireOrder(long orderId) {
        return orderDao.findById(orderId).orElseThrow(() -> new BizException("订单不存在"));
    }

    private boolean isStoreOwner(long userId, long storeId) {
        return storeDao.findById(storeId).map(store -> store.ownerId() == userId).orElse(false);
    }

    private boolean isExpired(String expireTime) {
        try {
            return LocalDateTime.parse(expireTime, FMT).isBefore(LocalDateTime.now());
        } catch (DateTimeParseException e) {
            return true;
        }
    }

    private void requireStatus(Order order, int expected) {
        if (order.status() != expected) {
            throw new BizException("订单状态不允许该操作（当前状态码 " + order.status() + "）");
        }
    }

    private Order.OrderView toView(Order order) {
        List<Order.OrderItem> items = parseItems(order.items());
        Order.AddressInfo address = parseAddress(order.address());
        return order.toView(items, address);
    }

    private List<Order.OrderItem> parseItems(String json) {
        try {
            return objectMapper.readValue(json, new TypeReference<List<Order.OrderItem>>() {
            });
        } catch (Exception e) {
            return List.of();
        }
    }

    private Order.AddressInfo parseAddress(String json) {
        try {
            return objectMapper.readValue(json, Order.AddressInfo.class);
        } catch (Exception e) {
            return new Order.AddressInfo(0, "", "", "");
        }
    }

    private String toJson(Object obj) {
        try {
            return objectMapper.writeValueAsString(obj);
        } catch (Exception e) {
            throw new BizException("数据序列化失败");
        }
    }

    private String genOrderNo() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"))
                + ThreadLocalRandom.current().nextInt(1000, 9999);
    }

    private static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }
}
