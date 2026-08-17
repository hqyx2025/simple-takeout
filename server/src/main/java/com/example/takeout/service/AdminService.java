package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.AdminStatsDao;
import com.example.takeout.dao.OrderDao;
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

    public AdminService(StoreDao storeDao, OrderDao orderDao, UserDao userDao, GoodsDao goodsDao,
                        RefundDao refundDao, OrderService orderService, AdminStatsDao adminStatsDao) {
        this.storeDao = storeDao;
        this.orderDao = orderDao;
        this.userDao = userDao;
        this.goodsDao = goodsDao;
        this.refundDao = refundDao;
        this.orderService = orderService;
        this.adminStatsDao = adminStatsDao;
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
        return storeDao.findCategoryById(id).orElseThrow(() -> new BizException("分类更新失败"));
    }

    public void deleteCategory(long id) {
        requirePlatformCategory(id);
        if (storeDao.countStoresByCategory(id) > 0) {
            throw new BizException("该分类仍有关联店铺，不能删除");
        }
        storeDao.deleteCategory(id);
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
    }

    public void updateStoreRecommended(long storeId, int recommended) {
        if (recommended != 0 && recommended != 1) {
            throw new BizException("推荐状态不合法");
        }
        storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        storeDao.updateRecommended(storeId, recommended);
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

    public List<AdminProduct> products(String keyword, Integer status) {
        if (status != null && status != 0 && status != 1) {
            throw new BizException("商品状态不合法");
        }
        return goodsDao.listForAdmin(keyword, status);
    }

    public void updateProductStatus(long id, int status) {
        if (status != 0 && status != 1) {
            throw new BizException("商品状态不合法");
        }
        goodsDao.findById(id).orElseThrow(() -> new BizException("商品不存在"));
        goodsDao.updateStatus(id, status);
    }

    public void deleteProduct(long id) {
        goodsDao.findById(id).orElseThrow(() -> new BizException("商品不存在"));
        goodsDao.delete(id);
    }

    public AdminStatistics statistics(int hotLimit) {
        return adminStatsDao.overview(hotLimit);
    }

    public List<AdminStatistics.TrendPoint> orderTrend(int days) {
        return adminStatsDao.orderTrend(days);
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
                orderDao.updateStatus(orderId, 2, "accept_time", now);
            }
            case "deliver" -> {
                requireStatus(order, 2);
                orderDao.updateStatus(orderId, 3, "deliver_time", now);
            }
            case "complete" -> {
                requireStatus(order, 3);
                orderDao.updateStatus(orderId, 4, "complete_time", now);
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

    @Transactional
    public Order.OrderView refundOrder(long orderId) {
        Order order = orderDao.findById(orderId).orElseThrow(() -> new BizException("订单不存在"));
        if (order.status() == 4) {
            throw new BizException("已送达订单不能直接退款，请走退款审批流程");
        }
        if (!orderDao.refundEscrow(orderId)) {
            throw new BizException("订单资金已处理，不能重复退款");
        }
        // escrow 条件更新成功才回滚库存（同一事务内，防重复回滚）
        Order.OrderView view = orderService.orderDetail(orderId);
        for (Order.OrderItem item : view.items()) {
            goodsDao.restoreStock(item.goodsId(), item.quantity());
        }
        User user = userDao.findById(order.userId()).orElseThrow(() -> new BizException("用户不存在"));
        userDao.updateBalance(user.id(), round2(user.balance() + order.payAmount()));
        orderDao.updateStatus(orderId, 5, "complete_time", now());
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
        User user = userDao.findById(order.userId()).orElseThrow(() -> new BizException("用户不存在"));
        userDao.updateBalance(user.id(), round2(user.balance() + order.payAmount()));
        Order.OrderView view = orderService.orderDetail(order.id());
        for (Order.OrderItem item : view.items()) {
            goodsDao.restoreStock(item.goodsId(), item.quantity());
        }
        refundDao.updateStatus(refundId, "REFUNDED", now(), "");
        return refundDao.findById(refundId).orElseThrow(() -> new BizException("退款处理失败"));
    }

    /** 拒绝退款：退款记录 REJECTED，订单状态回退到已送达（status=4），escrow 保持不变。 */
    @Transactional
    public RefundRecord rejectRefund(long refundId, String rejectReason) {
        RefundRecord record = requirePending(refundId);
        refundDao.updateStatus(refundId, "REJECTED", now(), rejectReason == null ? "" : rejectReason);
        orderDao.updateStatusOnly(record.orderId(), 4);
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

    private void validatePhone(String phone) {
        if (phone == null || !phone.matches("1\\d{10}")) {
            throw new BizException("手机号格式不正确");
        }
    }
}
