package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.CouponDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.ReviewDao;
import com.example.takeout.dao.RiderDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.Address;
import com.example.takeout.model.CartItemEntity;
import com.example.takeout.model.Coupon;
import com.example.takeout.model.Goods;
import com.example.takeout.model.GoodsSpec;
import com.example.takeout.model.Order;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.model.Review;
import com.example.takeout.model.Rider;
import com.example.takeout.model.Seckill;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.time.Duration;
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
    private final CartItemMapper cartItemMapper;
    private final RiderDao riderDao;
    private final GoodsSpecDao specDao;
    private final SeckillDao seckillDao;
    private final HotDataCacheService cache;
    private final DomainEventPublisher eventPublisher;
    private final ObjectProvider<StringRedisTemplate> redisProvider;

    /** 待付款订单的支付时限（分钟），超时由定时任务自动取消。 */
    @Value("${takeout.order.pay-timeout-minutes:15}")
    private int payTimeoutMinutes = 15;

    public OrderService(OrderDao orderDao, StoreDao storeDao, GoodsDao goodsDao, AddressDao addressDao,
                        CouponDao couponDao, ReviewDao reviewDao, UserDao userDao, RefundDao refundDao,
                        ObjectMapper objectMapper, CartItemMapper cartItemMapper, RiderDao riderDao,
                        GoodsSpecDao specDao, SeckillDao seckillDao, HotDataCacheService cache,
                        DomainEventPublisher eventPublisher,
                        ObjectProvider<StringRedisTemplate> redisProvider) {
        this.orderDao = orderDao;
        this.storeDao = storeDao;
        this.goodsDao = goodsDao;
        this.addressDao = addressDao;
        this.couponDao = couponDao;
        this.reviewDao = reviewDao;
        this.userDao = userDao;
        this.refundDao = refundDao;
        this.objectMapper = objectMapper;
        this.cartItemMapper = cartItemMapper;
        this.riderDao = riderDao;
        this.specDao = specDao;
        this.seckillDao = seckillDao;
        this.cache = cache;
        this.eventPublisher = eventPublisher;
        this.redisProvider = redisProvider;
    }

    /**
     * 库存/秒杀名额变化后的展示缓存失效。
     * 菜品库存与秒杀 sold 会直接影响店铺列表、店内菜品、特价菜、热销榜与秒杀专区的展示，
     * 因此这些聚合视图统一失效，避免用户看到「有货/有名额」的过期信息而下单失败。
     */
    private void invalidateStockDependentCache() {
        for (String pattern : HotDataCacheService.Keys.STOCK_DEPENDENT_PATTERNS) {
            cache.evictByPattern(pattern);
        }
    }

    /** 创建订单：从用户余额扣款后进入平台托管，状态=1 待接单。 */
    @Transactional
    public Order.OrderView createOrder(long userId, long storeId, List<Order.OrderItem> items,
                                       long addressId, long couponId, String remark) {
        return createOrder(userId, storeId, items, addressId, couponId, remark, List.of(), "");
    }

    /** 创建订单（兼容旧签名，立即送达）。 */
    @Transactional
    public Order.OrderView createOrder(long userId, long storeId, List<Order.OrderItem> items,
                                       long addressId, long couponId, String remark,
                                       List<Long> checkoutGoodsIds) {
        return createOrder(userId, storeId, items, addressId, couponId, remark, checkoutGoodsIds, "");
    }

    /** 创建订单：支持预约送达时间（expectTime 为空或“立即送达”表示立即配送）。 */
    @Transactional
    public Order.OrderView createOrder(long userId, long storeId, List<Order.OrderItem> items,
                                       long addressId, long couponId, String remark,
                                       List<Long> checkoutGoodsIds, String expectTime) {
        return createOrder(userId, storeId, items, addressId, couponId, remark, checkoutGoodsIds, expectTime, "");
    }

    /**
     * 创建订单完整签名：含 idempotencyKey 防重复提交。
     * 客户端生成一次性 token（如 UUID）随下单请求提交，服务端 Redis SET NX（5 分钟 TTL）拦截连点/网络重放；
     * Redis 不可用时跳过校验（与登录限流同口径：加固不能反过来让下单不可用）。
     * 下单失败时释放占位，用户修正后（如减少数量）可用同一 token 立即重试。
     */
    @Transactional
    public Order.OrderView createOrder(long userId, long storeId, List<Order.OrderItem> items,
                                       long addressId, long couponId, String remark,
                                       List<Long> checkoutGoodsIds, String expectTime,
                                       String idempotencyKey) {
        StringRedisTemplate redis = null;
        String redisKey = null;
        if (idempotencyKey != null && !idempotencyKey.isBlank()) {
            redis = redisProvider.getIfAvailable();
            if (redis != null) {
                redisKey = "takeout:idempotent:order:" + userId + ":" + idempotencyKey.trim();
                Boolean first = redis.opsForValue().setIfAbsent(redisKey, "1", Duration.ofMinutes(5));
                if (Boolean.FALSE.equals(first)) {
                    throw new BizException("订单正在提交中，请勿重复操作");
                }
            }
        }
        try {
            return doCreateOrder(userId, storeId, items, addressId, couponId, remark, checkoutGoodsIds, expectTime);
        } catch (RuntimeException e) {
            if (redisKey != null) {
                try {
                    redis.delete(redisKey);
                } catch (RuntimeException ignore) {
                    // 释放失败不掩盖原始异常；最坏退化为「同一 token 5 分钟内不能重试」
                }
            }
            throw e;
        }
    }

    private Order.OrderView doCreateOrder(long userId, long storeId, List<Order.OrderItem> items,
                                          long addressId, long couponId, String remark,
                                          List<Long> checkoutGoodsIds, String expectTime) {
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

        // 金额计算：商品总价 + 配送费 - 优惠（多规格取规格价，生效中的秒杀自动套用秒杀价）
        String now = LocalDateTime.now().format(FMT);
        double goodsAmount = 0;
        List<Order.OrderItem> normalizedItems = new ArrayList<>();
        List<StockHold> holds = new ArrayList<>();
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
            GoodsSpec spec = resolveSpec(goods, item.specId());
            int available = spec == null ? goods.stock() : spec.stock();
            if (available < item.quantity()) {
                throw new BizException("「" + goods.name() + "」库存不足，仅剩 " + available + " 件");
            }
            double unitPrice = spec == null ? goods.price() : spec.price();
            long seckillId = 0;
            if (spec == null) {
                // 限时秒杀：仅在时间窗口内且仍有名额时才按秒杀价结算，占不到名额则回退原价
                Seckill seckill = seckillDao.findActiveByGoods(goods.id(), now).orElse(null);
                if (seckill != null && seckillDao.deductQuota(seckill.id(), item.quantity(), now)) {
                    unitPrice = seckill.price();
                    seckillId = seckill.id();
                }
            }
            goodsAmount += unitPrice * item.quantity();
            normalizedItems.add(new Order.OrderItem(goods.id(), goods.name(), unitPrice, item.quantity(),
                    goods.image(), spec == null ? 0 : spec.id(), spec == null ? "" : spec.name(), seckillId));
            holds.add(new StockHold(goods.id(), spec == null ? 0 : spec.id(), item.quantity(), seckillId));
        }
        goodsAmount = round2(goodsAmount);
        double checkoutGoodsAmount = resolveCheckoutGoodsAmount(userId, storeId, checkoutGoodsIds, goodsAmount);
        if (checkoutGoodsAmount < store.minOrder()) {
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
        if (appliedCoupon != null && payAmount <= 0) {
            // 券面额吃掉全部货款时实付为 0：既无法走支付扣款，也会让「已扣款」口径失真。
            // 一律拒绝，且差额不退，提示用户换一张券。
            throw new BizException("优惠券抵扣后应付金额为 0，请更换优惠券");
        }

        // 待付款支付模型：下单只占用库存与优惠券，不扣余额；支付成功后才扣款并流转到待接单。
        if (appliedCoupon != null) {
            // 条件核销：并发下同一张券只能被一单使用，失败则回滚整单（库存/秒杀名额一并回滚）
            if (!couponDao.markUsed(appliedCoupon.id())) {
                throw new BizException("优惠券已被使用，请重新选择");
            }
        }
        // 扣减库存（乐观锁条件更新，防超卖）；任一失败整体回滚事务
        for (int i = 0; i < normalizedItems.size(); i++) {
            Order.OrderItem normalized = normalizedItems.get(i);
            StockHold hold = holds.get(i);
            if (!goodsDao.deductStock(normalized.goodsId(), normalized.quantity())) {
                throw new BizException("「" + normalized.goodsName() + "」库存不足，请减少数量或联系商家");
            }
            if (hold.specId() > 0 && !specDao.deductStock(hold.specId(), normalized.quantity())) {
                throw new BizException("「" + normalized.goodsName() + "」所选规格库存不足，请重新选择");
            }
        }

        String orderNo = genOrderNo();
        String normalizedExpect = normalizeExpectTime(expectTime);
        Order order = new Order(0, orderNo, userId, storeId, store.name(), 0,
                toJson(normalizedItems), toJson(new Order.AddressInfo(address.id(), address.name(), address.phone(), address.detail())),
                goodsAmount, store.deliveryFee(), discount, payAmount,
                remark == null ? "" : requireMaxLength(remark, 255, "订单备注"), 0, 0, now, "", "", "", "", normalizedExpect,
                appliedCoupon == null ? 0 : appliedCoupon.id());
        long id = orderDao.insert(order);
        storeDao.updateMonthlySales(storeId, 1);
        // 下单扣减了库存与秒杀名额，且店铺月销量变化会影响榜单，需失效相关展示缓存
        invalidateStockDependentCache();
        // 领域事件：与订单同事务写入 Outbox，提交后由中继投递到 Redis Stream
        eventPublisher.publish(DomainEventPublisher.ORDER_CREATED, id,
                Map.of("userId", userId, "storeId", storeId, "payAmount", payAmount));
        return orderDetail(id);
    }

    /** 下单时占用的库存 / 秒杀名额，取消或超时取消时按此回滚。 */
    private record StockHold(long goodsId, long specId, int quantity, long seckillId) {
    }

    /**
     * 支付待付款订单：扣除用户余额并流转到待接单（1）。
     * 条件更新失败说明订单已被取消/已支付，抛异常回滚余额扣减。
     */
    @Transactional
    public Order.OrderView payOrder(long userId, long orderId) {
        Order order = requireOrder(orderId);
        if (order.userId() != userId) {
            throw new BizException(403, "无权操作该订单");
        }
        if (order.status() != 0) {
            throw new BizException(order.status() == 5 ? "订单已取消，无法支付" : "订单已支付，请勿重复支付");
        }
        // 支付时限秒级显式检查：过了 payDeadline 的待付款订单不再接受支付（超时定时任务会竞争取消，
        // 这里提前拦下避免扣余额后才发现订单已被取消回滚；先查后改只影响几秒钟窗口，最终以条件更新为准）
        PayDeadline deadline = payDeadline(order);
        if (deadline.epochMs() > 0 && System.currentTimeMillis() > deadline.epochMs()) {
            throw new BizException("订单已超过支付时限，请重新下单");
        }
        User user = userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在"));
        if (user.balance() < order.payAmount()) {
            throw new BizException("余额不足，请先充值");
        }
        String now = LocalDateTime.now().format(FMT);
        if (!orderDao.markPaid(orderId, now)) {
            throw new BizException("订单状态已变化，请刷新后重试");
        }
        // 原子条件扣款：余额不足（并发支付两单时抢不到余额）即抛异常回滚订单状态，绝不写负余额
        if (!userDao.deductBalance(userId, order.payAmount())) {
            throw new BizException("余额不足，请先充值");
        }
        // 支付成功后才发出事件：条件更新失败会抛异常回滚，不会产生「假支付」事件
        eventPublisher.publish(DomainEventPublisher.ORDER_PAID, orderId,
                Map.of("userId", userId, "payAmount", order.payAmount()));
        return orderDetail(orderId);
    }

    /**
     * 待付款订单超时自动取消（定时任务入口）：超过支付时限仍未支付的订单一律取消，
     * 回滚库存、秒杀名额并释放优惠券。
     */
    @Transactional
    public int cancelExpiredPendingOrders() {
        String deadline = LocalDateTime.now().minusMinutes(Math.max(payTimeoutMinutes, 1)).format(FMT);
        int cancelled = 0;
        for (Order order : orderDao.listExpiredPending(deadline)) {
            if (cancelPending(order, "超时未支付，订单已自动取消")) {
                cancelled++;
            }
        }
        return cancelled;
    }

    /** 取消待付款订单：条件更新 0→5，成功后才回滚库存/名额并释放优惠券（同一事务）。 */
    private boolean cancelPending(Order order, String reason) {
        if (!orderDao.cancelPending(order.id(), LocalDateTime.now().format(FMT))) {
            return false;
        }
        rollbackStock(order);
        if (order.couponId() > 0) {
            couponDao.release(order.couponId(), LocalDateTime.now().format(FMT));
        }
        eventPublisher.publish(DomainEventPublisher.ORDER_CANCELLED, order.id(),
                Map.of("userId", order.userId(), "reason", reason == null ? "" : reason));
        return true;
    }


    private double resolveCheckoutGoodsAmount(long userId, long storeId, List<Long> checkoutGoodsIds, double currentStoreAmount) {
        if (checkoutGoodsIds == null || checkoutGoodsIds.isEmpty() || cartItemMapper == null) {
            return currentStoreAmount;
        }
        // 结算选择以「菜品」为粒度上报，而购物车行按 (菜品, 规格) 唯一：
        // 同一菜品选了多个规格时会上报重复的 goodsId，必须先去重再比对，否则永远撞「结算商品重复」。
        Set<Long> selectedIds = new HashSet<>(checkoutGoodsIds);
        List<CartItemEntity> cartItems = cartItemMapper.selectList(
                new com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper<CartItemEntity>()
                        .eq(CartItemEntity::getUserId, userId)
                        .in(CartItemEntity::getGoodsId, selectedIds));
        Set<Long> foundIds = new HashSet<>();
        double total = 0;
        for (CartItemEntity cartItem : cartItems) {
            Goods goods = goodsDao.findById(cartItem.getGoodsId())
                    .orElseThrow(() -> new BizException("购物车商品已不存在，请刷新后重试"));
            if (cartItem.getQuantity() == null || cartItem.getQuantity() <= 0) {
                throw new BizException("购物车商品数量无效，请刷新后重试");
            }
            foundIds.add(cartItem.getGoodsId());
            // 跨店结算时上报的是全部店铺的菜品，起送价只能按本店菜品计算，否则会被别店金额凑够门槛
            if (goods.storeId() != storeId) {
                continue;
            }
            total += unitPriceOf(goods, cartItem.getSpecId() == null ? 0 : cartItem.getSpecId())
                    * cartItem.getQuantity();
        }
        if (!foundIds.containsAll(selectedIds)) {
            throw new BizException("购物车商品已变化，请刷新后重试");
        }
        return round2(total);
    }

    /** 购物车行单价：多规格取规格价，无规格取菜品价。 */
    private double unitPriceOf(Goods goods, long specId) {
        if (specId <= 0) {
            return goods.price();
        }
        return goods.specs().stream()
                .filter(item -> item.id() == specId)
                .findFirst()
                .map(GoodsSpec::price)
                .orElseThrow(() -> new BizException("购物车商品规格已下架，请刷新后重试"));
    }

    public List<Order.OrderView> userOrders(long userId) {
        return orderDao.listByUser(userId).stream().map(this::toView).toList();
    }

    /**
     * 商户订单：仅可见自己店铺的订单
     * 待付款（status=0）订单尚未支付，不计入商户待处理列表（超时由定时任务自动取消）
     */
    public List<Order.OrderView> merchantOrders(long ownerId) {
        List<Store> stores = storeDao.listByOwner(ownerId);
        List<Long> storeIds = stores.stream().map(Store::id).toList();
        if (storeIds.isEmpty()) {
            return List.of();
        }
        return storeIds.stream()
                .flatMap(sid -> orderDao.listByStore(sid).stream())
                .filter(order -> order.status() != 0)
                .sorted((a, b) -> Long.compare(b.id(), a.id()))
                // 商户需要看到是谁接的单：骑手抢单后商户不再负责配送，界面上要能显示骑手并禁用商户侧流转按钮
                .map(this::toViewWithRider)
                .toList();
    }

    public Order.OrderView orderDetail(long id) {
        Order order = orderDao.findById(id).orElseThrow(() -> new BizException("订单不存在"));
        return toViewWithRider(order);
    }

    public Order.OrderView orderDetail(long requesterId, int role, long id) {
        Order order = requireOrder(id);
        if (order.userId() != requesterId && (role != 1 || !isStoreOwner(requesterId, order.storeId()))) {
            throw new BizException(403, "无权查看该订单");
        }
        return toViewWithRider(order);
    }

    // ============ 状态流转 ============

    @Transactional
    public Order.OrderView cancelOrder(long userId, long orderId) {
        Order order = requireOrder(orderId);
        if (order.userId() != userId) {
            throw new BizException(403, "无权操作该订单");
        }
        if (order.status() != 0 && order.status() != 1 && order.status() != 2 && order.status() != 3) {
            throw new BizException("当前状态不可取消");
        }
        // 待付款订单：尚未扣款，直接释放库存/秒杀名额与优惠券（escrow 保持未托管）
        if (order.status() == 0) {
            if (!cancelPending(order, "用户取消待付款订单")) {
                throw new BizException("订单状态已变化，请刷新后重试");
            }
            return orderDetail(orderId);
        }
        // 仅在托管状态下退款，条件更新避免重复退回余额。
        if (!orderDao.refundEscrow(orderId)) {
            throw new BizException("订单资金已处理，不能重复退款");
        }
        // 状态必须仍停留在取消时读到的状态：若期间已被骑手/商户推进到已送达，
        // 条件更新失败即抛异常回滚本事务的退款，避免「餐已送达还全额退款」。
        if (!orderDao.updateStatusFrom(orderId, order.status(), 5, "complete_time", LocalDateTime.now().format(FMT))) {
            throw new BizException("订单状态已变化，请刷新后重试");
        }
        // escrow 条件更新成功才回滚库存（同一事务内，防重复回滚）
        rollbackStock(order);
        userDao.addBalance(userId, order.payAmount());
        eventPublisher.publish(DomainEventPublisher.ORDER_CANCELLED, orderId,
                Map.of("userId", userId, "reason", "用户取消已支付订单，已即时退款"));
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
        // 条件流转 4→6（同时要求 escrow=0）：与「确认收货」并发时只有一方能成功，
        // 成功后才插入申请记录，重复点击/网络重放不会产生第二条 PENDING。
        if (!orderDao.markRefunding(orderId)) {
            throw new BizException("订单资金已处理或状态已变化，请刷新后重试");
        }
        Store store = storeDao.findById(order.storeId()).orElseThrow(() -> new BizException("店铺不存在"));
        String now = LocalDateTime.now().format(FMT);
        String safeReason = requireMaxLength(reason == null ? "" : reason, 255, "退款原因");
        long id = refundDao.insert(orderId, userId, store.ownerId(),
                safeReason, order.payAmount(), now);
        return refundDao.findById(id).orElseThrow(() -> new BizException("退款申请失败"));
    }

    /** 回滚订单商品库存与秒杀名额（取消/退款时调用，必须在条件更新成功后的同一事务内）。 */
    void rollbackStock(Order order) {
        for (Order.OrderItem item : parseItems(order.items())) {
            goodsDao.restoreStock(item.goodsId(), item.quantity());
            if (item.specId() > 0) {
                specDao.restoreStock(item.specId(), item.quantity());
            }
            if (item.seckillId() > 0) {
                seckillDao.restoreQuota(item.seckillId(), item.quantity());
            }
        }
        // 库存与秒杀名额已归还，让展示层重新读取真实余量
        invalidateStockDependentCache();
    }

    /**
     * 校验并解析下单所用规格：多规格菜品必须带 specId，无规格菜品不得带 specId。
     */
    private GoodsSpec resolveSpec(Goods goods, long specId) {
        if (goods.multiSpec()) {
            if (specId <= 0) {
                throw new BizException("「" + goods.name() + "」请先选择规格");
            }
            return goods.specs().stream()
                    .filter(item -> item.id() == specId)
                    .findFirst()
                    .orElseThrow(() -> new BizException("「" + goods.name() + "」所选规格已下架，请重新选择"));
        }
        if (specId > 0) {
            throw new BizException("「" + goods.name() + "」不支持规格选择");
        }
        return null;
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
                requireStatusUpdated(orderDao.updateStatusFrom(orderId, 1, 2, "accept_time", now));
            }
            case "ready" -> {           // 出餐完成：写 ready_time，进入骑手待取餐池（数字状态仍为 2）
                requireStatus(order, 2);
                if (!orderDao.markReady(orderId, now)) {
                    throw new BizException("该订单已出餐，请勿重复操作");
                }
            }
            case "deliver" -> {         // 出餐配送：2 → 3（仅未分配骑手的订单，避免与骑手流程冲突）
                requireStatus(order, 2);
                requireNoRider(orderId);
                requireStatusUpdated(orderDao.merchantDeliver(orderId, now));
            }
            case "complete" -> {        // 确认送达：3 → 4（仅未分配骑手的订单）
                requireStatus(order, 3);
                requireNoRider(orderId);
                requireStatusUpdated(orderDao.merchantComplete(orderId, now));
            }
            default -> throw new BizException("不支持的操作：" + action);
        }
        return orderDetail(orderId);
    }

    // ============ 四端改造：骑手配送 ============

    /** 待取餐池：已出餐且尚未分配骑手。 */
    public List<Order.OrderView> riderPool() {
        return orderDao.listRiderPool().stream().map(this::toView).toList();
    }

    /** 抢单/取餐/送达前校验骑手未被平台停用（控制器已做在线校验，服务层做独立防御）。 */
    private void requireActiveRider(long riderId) {
        Rider rider = riderDao.findById(riderId).orElseThrow(() -> new BizException("骑手不存在"));
        if (rider.status() != 1) {
            throw new BizException(403, "骑手账号已停用，请联系平台管理员");
        }
    }

    /** 骑手抢单：条件更新，防并发重复抢单。 */
    @Transactional
    public Order.OrderView riderGrab(long riderId, long orderId) {
        requireActiveRider(riderId);
        if (!orderDao.tryAssignRider(orderId, riderId)) {
            throw new BizException("手慢了，该订单已被其他骑手接走");
        }
        return orderDetail(orderId);
    }

    /** 骑手取餐：2 → 3（仅本人接单的订单）。 */
    @Transactional
    public Order.OrderView riderPickup(long riderId, long orderId) {
        requireActiveRider(riderId);
        String now = LocalDateTime.now().format(FMT);
        if (!orderDao.riderPickup(orderId, riderId, now)) {
            throw new BizException("无法取餐：请确认已接单且商家已出餐");
        }
        return orderDetail(orderId);
    }

    /** 骑手送达：3 → 4（仅本人配送的订单），单量与配送收入在同一事务内累加。 */
    @Transactional
    public Order.OrderView riderDeliver(long riderId, long orderId) {
        requireActiveRider(riderId);
        String now = LocalDateTime.now().format(FMT);
        if (!orderDao.riderDeliver(orderId, riderId, now)) {
            throw new BizException("无法送达：请确认已取餐且由你配送");
        }
        // 与订单状态同事务：否则订单已置 4 而收入累加失败时，重试会被条件更新拒绝，
        // 骑手单量/收入永久少记一笔且无补偿路径。
        Order order = orderDao.findById(orderId).orElseThrow(() -> new BizException("订单不存在"));
        riderDao.addCompleted(riderId, order.deliveryFee());
        return orderDetail(orderId);
    }

    /** 骑手的配送单列表。 */
    public List<Order.OrderView> riderOrders(long riderId) {
        return orderDao.listByRider(riderId).stream().map(this::toView).toList();
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
        // 原子加款：并发确认/退款下不会互相覆盖余额
        userDao.addBalance(merchant.id(), order.payAmount());
        return orderDetail(orderId);
    }

    /**
     * 评价已完成订单（兼容旧签名，默认评价订单内第一个商品）
     */
    @Transactional
    public Review reviewOrder(long userId, long orderId, int rating, String content, List<String> tags) {
        return reviewOrder(userId, orderId, 0, rating, content, tags, List.of(), 0);
    }

    /** 评价已完成订单中的一个具体商品（兼容旧签名，无图、非匿名）。 */
    @Transactional
    public Review reviewOrder(long userId, long orderId, long goodsId, int rating, String content, List<String> tags) {
        return reviewOrder(userId, orderId, goodsId, rating, content, tags, List.of(), 0);
    }

    /**
     * 按菜品评价：一个订单内的每个商品可分别评价，评价后重算店铺/商品评分；
     * 订单内全部商品评价完才将 orders.reviewed 置 1。
     */
    @Transactional
    public Review reviewOrder(long userId, long orderId, long goodsId, int rating, String content,
                              List<String> tags, List<String> images, int anonymous) {
        Order order = requireOrder(orderId);
        if (order.userId() != userId) {
            throw new BizException(403, "无权评价该订单");
        }
        if (order.status() != 4 || order.escrowStatus() != 1) {
            throw new BizException("确认收货并结算后才能评价商品");
        }
        if (rating < 1 || rating > 5) {
            throw new BizException("评分范围 1-5");
        }
        User user = userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在"));
        List<Order.OrderItem> orderItems = parseItems(order.items());
        long targetGoodsId = goodsId;
        if (targetGoodsId <= 0 && !orderItems.isEmpty()) {
            targetGoodsId = orderItems.get(0).goodsId();
        }
        final long selectedGoodsId = targetGoodsId;
        orderItems.stream()
                .filter(item -> item.goodsId() == selectedGoodsId)
                .findFirst()
                .orElseThrow(() -> new BizException("评价商品不在该订单中"));
        if (reviewDao.existsByOrderGoods(orderId, selectedGoodsId)) {
            throw new BizException("该商品已评价");
        }
        String now = LocalDateTime.now().format(FMT);
        long reviewId = reviewDao.insert(orderId, order.storeId(), selectedGoodsId, userId, user.username(),
                rating, requireMaxLength(content, 512, "评价内容"), toJson(tags == null ? List.of() : tags),
                toJson(images == null ? List.of() : images), anonymous == 0 ? 0 : 1, now);
        // 评价后重算店铺与商品平均评分
        storeDao.updateRating(order.storeId(), round1(reviewDao.avgRating(order.storeId())));
        goodsDao.updateRating(selectedGoodsId, round1(reviewDao.avgGoodsRating(selectedGoodsId)));
        // 订单内全部商品评价完才标记整单已评价
        long distinctGoods = orderItems.stream().map(Order.OrderItem::goodsId).distinct().count();
        if (reviewDao.countByOrder(orderId) >= distinctGoods) {
            orderDao.markReviewed(orderId);
        }
        return reviewDao.findById(reviewId).orElseThrow(() -> new BizException("评价失败"));
    }

    // ============ 商户统计 ============

    /**
     * 商户统计：固定返回今日/本周/本月三档（周一为一周起点，与前端 AppStorageManager 口径一致）。
     * 不接收 range 参数——历史上它被声明过却从未使用，非法值还会被静默忽略，
     * 与其留一个骗人的入参，不如让接口签名如实反映"三档一起返回"。
     */
    public MerchantStats merchantStats(long ownerId, long storeId) {
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
        } catch (Exception e) {
            // 含 null：券过期时间缺失一律按已过期处理，不能抛 NPE 变成 500
            return true;
        }
    }

    private void requireStatus(Order order, int expected) {
        if (order.status() != expected) {
            throw new BizException("订单状态不允许该操作（当前状态码 " + order.status() + "）");
        }
    }

    /** 条件状态更新失败 = 期间已被其它操作改变（用户取消/骑手接单），必须回滚整单。 */
    private void requireStatusUpdated(boolean updated) {
        if (!updated) {
            throw new BizException("订单状态已变化，请刷新后重试");
        }
    }

    /** 长度上限校验：列宽有限，超长会在写库时抛 500，这里提前给出可读的 400 提示。 */
    private static String requireMaxLength(String value, int max, String field) {
        String safe = value == null ? "" : value;
        if (safe.length() > max) {
            throw new BizException(field + "最多 " + max + " 个字符");
        }
        return safe;
    }

    /** 四端改造：订单一旦分配骑手，配送与送达只能由骑手完成，商户不得再操作。 */
    private void requireNoRider(long orderId) {
        if (orderDao.findRiderId(orderId) > 0) {
            throw new BizException("该订单已由骑手配送，商户无需操作");
        }
    }

    /**
     * 预约送达时间归一化：空 / “立即送达” → 立即配送（空串）；
     * 否则必须是合法且晚于当前时间的 yyyy-MM-dd HH:mm:ss。
     */
    private String normalizeExpectTime(String expectTime) {
        if (expectTime == null || expectTime.isBlank() || "立即送达".equals(expectTime.trim())) {
            return "";
        }
        String value = expectTime.trim();
        try {
            LocalDateTime target = LocalDateTime.parse(value, FMT);
            if (target.isBefore(LocalDateTime.now())) {
                throw new BizException("预约送达时间必须晚于当前时间");
            }
            return value;
        } catch (java.time.format.DateTimeParseException e) {
            throw new BizException("预约送达时间格式不正确");
        }
    }

    private Order.OrderView toView(Order order) {
        List<Order.OrderItem> items = parseItems(order.items());
        Order.AddressInfo address = parseAddress(order.address());
        var deadline = payDeadline(order);
        return order.toView(items, address, deadline.text, deadline.epochMs, "", "", "");
    }

    /** 待付款订单的支付截止时间（前端倒计时用）；非待付款返回空串和0。 */
    private record PayDeadline(String text, long epochMs) {}

    private PayDeadline payDeadline(Order order) {
        if (order.status() != 0) {
            return new PayDeadline("", 0L);
        }
        try {
            var deadline = LocalDateTime.parse(order.createTime(), FMT)
                    .plusMinutes(Math.max(payTimeoutMinutes, 1));
            long epochMs = deadline.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli();
            return new PayDeadline(deadline.format(FMT), epochMs);
        } catch (DateTimeParseException e) {
            return new PayDeadline("", 0L);
        }
    }

    /** 订单详情视图：附带骑手姓名/电话（未分配骑手时为空）与出餐时间（未出餐为空）。 */
    private Order.OrderView toViewWithRider(Order order) {
        List<Order.OrderItem> items = parseItems(order.items());
        Order.AddressInfo address = parseAddress(order.address());
        String riderName = "";
        String riderPhone = "";
        if (riderDao != null) {
            long riderId = orderDao.findRiderId(order.id());
            if (riderId > 0) {
                Rider rider = riderDao.findById(riderId).orElse(null);
                if (rider != null) {
                    riderName = rider.name();
                    riderPhone = rider.phone();
                }
            }
        }
        var deadline = payDeadline(order);
        return order.toView(items, address, deadline.text, deadline.epochMs, riderName, riderPhone,
                orderDao.findReadyTime(order.id()));
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

    private static double round1(double v) {
        return Math.round(v * 10.0) / 10.0;
    }
}
