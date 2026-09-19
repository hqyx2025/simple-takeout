package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.AdminStatsDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Category;
import com.example.takeout.model.AdminEmployee;
import com.example.takeout.model.AdminProduct;
import com.example.takeout.model.AdminStatistics;
import com.example.takeout.model.AdminUser;
import com.example.takeout.model.Order;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import com.example.takeout.security.PasswordUtil;
import com.example.takeout.service.mq.DomainEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/** 管理端业务：分类、店铺状态和平台订单/托管款管理。 */
@Service
public class AdminService {

    private final StoreDao storeDao;
    private final OrderDao orderDao;
    private final UserDao userDao;
    private final GoodsDao goodsDao;
    private final RefundDao refundDao;
    private final OrderService orderService;
    private final AdminStatsDao adminStatsDao;
    private final HotDataCacheService cache;
    private final DomainEventPublisher eventPublisher;
    private final PaymentRecordDao paymentRecordDao;

    public AdminService(StoreDao storeDao, OrderDao orderDao, UserDao userDao, GoodsDao goodsDao,
                        RefundDao refundDao, OrderService orderService, AdminStatsDao adminStatsDao,
                        HotDataCacheService cache, DomainEventPublisher eventPublisher,
                        PaymentRecordDao paymentRecordDao) {
        this.storeDao = storeDao;
        this.orderDao = orderDao;
        this.userDao = userDao;
        this.goodsDao = goodsDao;
        this.refundDao = refundDao;
        this.orderService = orderService;
        this.adminStatsDao = adminStatsDao;
        this.cache = cache;
        this.eventPublisher = eventPublisher;
        this.paymentRecordDao = paymentRecordDao;
    }

    /**
     * 平台分类、店铺状态/推荐位、商品上下架与删除都会改变用户端展示结果，
     * 统一失效店铺与商品相关缓存，避免首页长时间显示过期数据。
     */
    private void invalidateStoreAndGoodsCache() {
        for (String pattern : HotDataCacheService.Keys.STORE_GOODS_PATTERNS) {
            cache.evictByPattern(pattern);
        }
    }

    public List<Category> categories() {
        return storeDao.listCategories();
    }

    public Category createCategory(String name, String icon, String color) {
        String normalizedName = normalizeRequired(name, "分类名称不能为空");
        if (storeDao.categoryNameExists(normalizedName, 0)) {
            throw new BizException("分类名称已存在");
        }
        long id = storeDao.insertCategory(normalizedName,
                icon == null ? "" : icon.trim(),
                color == null || color.isBlank() ? "#FF6B35" : color.trim());
        invalidateStoreAndGoodsCache();
        return storeDao.findCategoryById(id).orElseThrow(() -> new BizException("分类创建失败"));
    }

    public Category updateCategory(long id, String name, String icon, String color) {
        requirePlatformCategory(id);
        String normalizedName = normalizeRequired(name, "分类名称不能为空");
        if (storeDao.categoryNameExists(normalizedName, id)) {
            throw new BizException("分类名称已存在");
        }
        storeDao.updateCategory(id, normalizedName, icon == null ? "" : icon.trim(),
                color == null || color.isBlank() ? "#FF6B35" : color.trim());
        invalidateStoreAndGoodsCache();
        return storeDao.findCategoryById(id).orElseThrow(() -> new BizException("分类更新失败"));
    }

    public void deleteCategory(long id) {
        requirePlatformCategory(id);
        if (storeDao.countStoresByCategory(id) > 0) {
            throw new BizException("该分类仍有关联店铺，不能删除");
        }
        storeDao.deleteCategory(id);
        invalidateStoreAndGoodsCache();
    }

    public List<Store.StoreView> stores() {
        return storeDao.listAllForAdmin().stream().map(this::toStoreView).toList();
    }

    public void updateStoreStatus(long storeId, int status) {
        if (status != 0 && status != 1) {
            throw new BizException("店铺状态不合法");
        }
        storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        storeDao.updateStatus(storeId, status);
        invalidateStoreAndGoodsCache();
    }

    public void updateStoreRecommended(long storeId, int recommended) {
        if (recommended != 0 && recommended != 1) {
            throw new BizException("推荐状态不合法");
        }
        storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        storeDao.updateRecommended(storeId, recommended);
        invalidateStoreAndGoodsCache();
    }

    public List<Order.OrderView> orders() {
        return orderDao.listAll().stream().map(order -> orderService.orderDetail(order.id())).toList();
    }

    public List<AdminEmployee> employees() {
        return userDao.listEmployees();
    }

    public List<AdminUser> users(Integer role, Integer status, String keyword) {
        if (role != null && role != 0 && role != 1) {
            throw new BizException("用户角色筛选不合法");
        }
        if (status != null && status != 0 && status != 1) {
            throw new BizException("账号状态筛选不合法");
        }
        return userDao.listForAdmin(role, status, keyword);
    }

    public void updateUserStatus(long id, int status) {
        if (status != 0 && status != 1) {
            throw new BizException("账号状态不合法");
        }
        User user = userDao.findById(id).orElseThrow(() -> new BizException("用户不存在"));
        if (user.role() == 2) {
            throw new BizException("管理员账号不能在此处停用");
        }
        userDao.updateStatus(id, status);
    }

    public AdminService.ProductPage products(String keyword, Integer status, int page, int pageSize) {
        if (status != null && status != 0 && status != 1) {
            throw new BizException("商品状态不合法");
        }
        int size = Math.clamp(pageSize, 1, 100);
        int current = Math.max(page, 1);
        int total = goodsDao.countForAdmin(keyword, status);
        List<AdminProduct> list = goodsDao.listForAdmin(keyword, status, size, (current - 1) * size);
        return new AdminService.ProductPage(list, total, current, size, current * size < total);
    }

    /** 管理端商品分页结果。 */
    public record ProductPage(List<AdminProduct> list, int total, int page, int pageSize, boolean hasMore) {
    }

    public void updateProductStatus(long id, int status) {
        if (status != 0 && status != 1) {
            throw new BizException("商品状态不合法");
        }
        goodsDao.findById(id).orElseThrow(() -> new BizException("商品不存在"));
        goodsDao.updateStatus(id, status);
        invalidateStoreAndGoodsCache();
    }

    public void deleteProduct(long id) {
        goodsDao.findById(id).orElseThrow(() -> new BizException("商品不存在"));
        goodsDao.delete(id);
        invalidateStoreAndGoodsCache();
    }

    public AdminStatistics statistics(int hotLimit) {
        return adminStatsDao.overview(hotLimit);
    }

    public List<AdminStatistics.TrendPoint> orderTrend(int days) {
        return adminStatsDao.orderTrend(days);
    }

    /** 数据大屏：一次性汇聚 关键指标 + 7 日趋势 + 订单状态分布 + 店铺成交额排行。 */
    public Dashboard dashboard(int hotLimit) {
        return new Dashboard(adminStatsDao.overview(hotLimit), adminStatsDao.orderTrend(7),
                adminStatsDao.orderStatusCounts(), adminStatsDao.topStores(10));
    }

    public record Dashboard(AdminStatistics overview, List<AdminStatistics.TrendPoint> trend,
                            List<AdminStatistics.OrderStatusCount> orderStatuses,
                            List<AdminStatistics.TopStore> topStores) {
    }

    public AdminEmployee createEmployee(String username, String phone, String password) {
        String normalizedName = normalizeRequired(username, "员工姓名不能为空");
        validatePhone(phone);
        if (password == null || password.length() < 6) {
            throw new BizException("员工初始密码至少 6 位");
        }
        if (userDao.existsByPhone(phone)) {
            throw new BizException("手机号已注册");
        }
        return userDao.insertEmployee(normalizedName, phone, PasswordUtil.hash(password), now());
    }

    public AdminEmployee updateEmployee(long id, String username, String phone) {
        userDao.listEmployees().stream().filter(employee -> employee.id() == id).findFirst()
                .orElseThrow(() -> new BizException("员工不存在"));
        String normalizedName = normalizeRequired(username, "员工姓名不能为空");
        validatePhone(phone);
        if (userDao.existsByPhoneExceptUser(phone, id)) {
            throw new BizException("手机号已被其他账号使用");
        }
        userDao.updateEmployee(id, normalizedName, phone);
        return userDao.listEmployees().stream().filter(employee -> employee.id() == id).findFirst()
                .orElseThrow(() -> new BizException("员工更新失败"));
    }

    public void updateEmployeeStatus(long id, int status) {
        if (status != 0 && status != 1) {
            throw new BizException("员工状态不合法");
        }
        userDao.listEmployees().stream().filter(employee -> employee.id() == id).findFirst()
                .orElseThrow(() -> new BizException("员工不存在"));
        userDao.updateEmployeeStatus(id, status);
    }

    /** 管理端订单推进：用于平台异常运营处理，状态规则与商户端一致。 */
    @Transactional
    public Order.OrderView orderFlow(long orderId, String action) {
        Order order = orderDao.findById(orderId).orElseThrow(() -> new BizException("订单不存在"));
        String now = now();
        switch (action) {
            case "accept" -> {
                requireStatus(order, 1);
                requireStatusUpdated(orderDao.updateStatusFrom(orderId, 1, 2, "accept_time", now));
            }
            case "ready" -> {
                // 出餐完成：只写 ready_time，状态保持 2，订单由此进入骑手待取餐池。
                // 若这里走 deliver(2→3)，订单会永久跳过骑手（池子按 status=2 + ready_time 筛选）。
                requireStatus(order, 2);
                if (!orderDao.markReady(orderId, now)) {
                    throw new BizException("该订单已出餐，请勿重复操作");
                }
            }
            case "deliver" -> {
                requireStatus(order, 2);
                requireNoRider(order);
                requireStatusUpdated(orderDao.merchantDeliver(orderId, now));
            }
            case "complete" -> {
                requireStatus(order, 3);
                requireNoRider(order);
                requireStatusUpdated(orderDao.merchantComplete(orderId, now));
            }
            case "cancel" -> {
                if (order.status() != 1 && order.status() != 2 && order.status() != 3) {
                    throw new BizException("当前状态不可取消");
                }
                return refundOrder(orderId);
            }
            default -> throw new BizException("不支持的订单操作：" + action);
        }
        return orderService.orderDetail(orderId);
    }

    /** 已由骑手接单的订单由骑手负责配送，平台侧不再代为流转。 */
    private void requireNoRider(Order order) {
        if (orderDao.findRiderId(order.id()) > 0) {
            throw new BizException("该订单已由骑手配送，无需平台操作");
        }
    }

    @Transactional
    public Order.OrderView refundOrder(long orderId) {
        Order order = orderDao.findById(orderId).orElseThrow(() -> new BizException("订单不存在"));
        // 只有「已扣款且尚未送达」的订单才存在可退的托管资金：待付款(0)、待付款取消(5) 的
        // escrow 同样是 0，若只看 escrow 就会对从未扣款的订单退款，凭空给用户加钱。
        if (order.status() != 1 && order.status() != 2 && order.status() != 3) {
            throw new BizException("当前状态不可直接退款（已送达请走退款审批，未支付无需退款）");
        }
        if (!orderDao.refundEscrow(orderId)) {
            throw new BizException("订单资金已处理，不能重复退款");
        }
        if (!orderDao.updateStatusFrom(orderId, order.status(), 5, "complete_time", now())) {
            throw new BizException("订单状态已变化，请刷新后重试");
        }
        // escrow 条件更新成功才回滚库存（同一事务内，防重复回滚）；
        // 复用 OrderService 的回滚：goods 库存、规格库存、秒杀名额三者缺一不可
        orderService.rollbackStock(order);
        userDao.addBalance(order.userId(), order.payAmount());
        // 已回滚库存，用户端展示需重新读取真实余量
        invalidateStoreAndGoodsCache();
        return orderService.orderDetail(orderId);
    }

    // ============ 退款审批（演进项，见大纲 9.7/10.7） ============

    public List<RefundRecord> refunds(String status) {
        return status == null || status.isBlank() ? refundDao.listAll() : refundDao.listByStatus(status);
    }

    public RefundRecord refundDetail(long refundId) {
        return refundDao.findById(refundId).orElseThrow(() -> new BizException("退款申请不存在"));
    }

    /** 同意退款：escrow 0→2（条件更新）→ 退用户余额 → 回滚库存 → 退款记录 REFUNDED。 */
    @Transactional
    public RefundRecord approveRefund(long refundId) {
        RefundRecord record = requirePending(refundId);
        Order order = orderDao.findById(record.orderId()).orElseThrow(() -> new BizException("订单不存在"));
        if (!orderDao.refundEscrow(order.id())) {
            throw new BizException("订单资金已处理，不能重复退款");
        }
        userDao.addBalance(order.userId(), order.payAmount());
        paymentRecordDao.insert(order.id(), order.userId(), order.payAmount(), "REFUND", "BALANCE", "SUCCESS", now());
        // 复用统一回滚：goods 库存 + 规格库存 + 秒杀名额，避免规格库存与秒杀名额泄漏
        orderService.rollbackStock(order);
        refundDao.updateStatus(refundId, "REFUNDED", now(), "");
        // 同意退款已回滚库存，失效相关展示缓存
        invalidateStoreAndGoodsCache();
        // 领域事件：与退款状态更新同事务写入 Outbox，提交后异步投递
        eventPublisher.publish(DomainEventPublisher.ORDER_REFUNDED, order.id(),
                java.util.Map.of("userId", order.userId(), "refundId", refundId));
        return refundDao.findById(refundId).orElseThrow(() -> new BizException("退款处理失败"));
    }

    /** 拒绝退款：退款记录 REJECTED，订单状态回退到已送达（status=4），escrow 保持不变。 */
    @Transactional
    public RefundRecord rejectRefund(long refundId, String rejectReason) {
        RefundRecord record = requirePending(refundId);
        refundDao.updateStatus(refundId, "REJECTED", now(), rejectReason == null ? "" : rejectReason);
        // 订单回退到已送达：仅当仍处于退款中(6) 时回退，已是 4 则按幂等处理（退款记录才是审批事实）
        orderDao.updateStatusOnlyFrom(record.orderId(), 6, 4);
        return refundDao.findById(refundId).orElseThrow(() -> new BizException("退款处理失败"));
    }

    private RefundRecord requirePending(long refundId) {
        RefundRecord record = refundDao.findById(refundId).orElseThrow(() -> new BizException("退款申请不存在"));
        if (!"PENDING".equals(record.status())) {
            throw new BizException("该退款申请已处理");
        }
        return record;
    }

    private Store.StoreView toStoreView(Store store) {
        return store.toView(List.of(), List.of());
    }

    private Category requirePlatformCategory(long id) {
        Category category = storeDao.findCategoryById(id).orElseThrow(() -> new BizException("分类不存在"));
        if (!"PLATFORM".equals(category.type())) {
            throw new BizException("只能管理平台分类");
        }
        return category;
    }

    private String normalizeRequired(String value, String message) {
        if (value == null || value.isBlank()) {
            throw new BizException(message);
        }
        return value.trim();
    }

    private String now() {
        return java.time.LocalDateTime.now().format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }

    private double round2(double value) {
        return Math.round(value * 100.0) / 100.0;
    }

    private void requireStatus(Order order, int expected) {
        if (order.status() != expected) {
            throw new BizException("订单当前状态不支持该操作");
        }
    }

    /** 条件状态更新失败 = 期间已被其它操作改变（用户取消/骑手接单），必须回滚整单。 */
    private void requireStatusUpdated(boolean updated) {
        if (!updated) {
            throw new BizException("订单状态已变化，请刷新后重试");
        }
    }

    private void validatePhone(String phone) {
        if (phone == null || !phone.matches("1\\d{10}")) {
            throw new BizException("手机号格式不正确");
        }
    }
}
