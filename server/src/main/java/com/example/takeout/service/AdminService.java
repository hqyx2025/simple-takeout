package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Category;
import com.example.takeout.model.Order;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/** 管理端业务：分类、店铺状态和平台订单/托管款管理。 */
@Service
public class AdminService {

    private final StoreDao storeDao;
    private final OrderDao orderDao;
    private final UserDao userDao;
    private final OrderService orderService;

    public AdminService(StoreDao storeDao, OrderDao orderDao, UserDao userDao, OrderService orderService) {
        this.storeDao = storeDao;
        this.orderDao = orderDao;
        this.userDao = userDao;
        this.orderService = orderService;
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
        storeDao.findCategoryById(id).orElseThrow(() -> new BizException("分类不存在"));
        String normalizedName = normalizeRequired(name, "分类名称不能为空");
        if (storeDao.categoryNameExists(normalizedName, id)) {
            throw new BizException("分类名称已存在");
        }
        storeDao.updateCategory(id, normalizedName, icon == null ? "" : icon.trim(),
                color == null || color.isBlank() ? "#FF6B35" : color.trim());
        return storeDao.findCategoryById(id).orElseThrow(() -> new BizException("分类更新失败"));
    }

    public void deleteCategory(long id) {
        storeDao.findCategoryById(id).orElseThrow(() -> new BizException("分类不存在"));
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

    public List<Order.OrderView> orders() {
        return orderDao.listAll().stream().map(order -> orderService.orderDetail(order.id())).toList();
    }

    @Transactional
    public Order.OrderView refundOrder(long orderId) {
        Order order = orderDao.findById(orderId).orElseThrow(() -> new BizException("订单不存在"));
        if (order.status() == 4) {
            throw new BizException("已送达订单不能直接退款");
        }
        if (!orderDao.refundEscrow(orderId)) {
            throw new BizException("订单资金已处理，不能重复退款");
        }
        User user = userDao.findById(order.userId()).orElseThrow(() -> new BizException("用户不存在"));
        userDao.updateBalance(user.id(), round2(user.balance() + order.payAmount()));
        orderDao.updateStatus(orderId, 5, "complete_time", now());
        return orderService.orderDetail(orderId);
    }

    private Store.StoreView toStoreView(Store store) {
        return store.toView(List.of(), List.of());
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
}
