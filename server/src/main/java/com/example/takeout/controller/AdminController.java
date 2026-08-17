package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.model.Category;
import com.example.takeout.model.AdminEmployee;
import com.example.takeout.model.AdminProduct;
import com.example.takeout.model.AdminStatistics;
import com.example.takeout.model.AdminUser;
import com.example.takeout.model.Order;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.model.Store;
import com.example.takeout.service.AdminService;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** 管理端接口，所有接口要求 role=2。 */
@RestController
@RequestMapping("/api/admin")
public class AdminController {

    private final AdminService adminService;

    public AdminController(AdminService adminService) {
        this.adminService = adminService;
    }

    @GetMapping("/categories")
    public ApiResponse<List<Category>> categories(@RequestAttribute("role") int role) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.categories());
    }

    @PostMapping("/categories")
    public ApiResponse<Category> createCategory(@RequestAttribute("role") int role,
                                                 @RequestBody CategoryRequest req) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.createCategory(req.name(), req.icon(), req.color()));
    }

    @PutMapping("/categories/{id}")
    public ApiResponse<Category> updateCategory(@RequestAttribute("role") int role,
                                                 @PathVariable long id,
                                                 @RequestBody CategoryRequest req) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.updateCategory(id, req.name(), req.icon(), req.color()));
    }

    @DeleteMapping("/categories/{id}")
    public ApiResponse<Void> deleteCategory(@RequestAttribute("role") int role, @PathVariable long id) {
        requireAdmin(role);
        adminService.deleteCategory(id);
        return ApiResponse.ok();
    }

    @GetMapping("/stores")
    public ApiResponse<List<Store.StoreView>> stores(@RequestAttribute("role") int role) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.stores());
    }

    @PutMapping("/stores/{id}/status")
    public ApiResponse<Void> updateStoreStatus(@RequestAttribute("role") int role,
                                                @PathVariable long id,
                                                @RequestBody StoreStatusRequest req) {
        requireAdmin(role);
        adminService.updateStoreStatus(id, req.status());
        return ApiResponse.ok();
    }

    @GetMapping("/orders")
    public ApiResponse<List<Order.OrderView>> orders(@RequestAttribute("role") int role) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.orders());
    }

    @PutMapping("/orders/{id}/refund")
    public ApiResponse<Order.OrderView> refund(@RequestAttribute("role") int role, @PathVariable long id) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.refundOrder(id));
    }

    @PutMapping("/orders/{id}/{action}")
    public ApiResponse<Order.OrderView> orderFlow(@RequestAttribute("role") int role,
                                                   @PathVariable long id,
                                                   @PathVariable String action) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.orderFlow(id, action));
    }

    // ============ 员工管理 ============

    @GetMapping("/employees")
    public ApiResponse<List<AdminEmployee>> employees(@RequestAttribute("role") int role) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.employees());
    }

    @GetMapping("/users")
    public ApiResponse<List<AdminUser>> users(@RequestAttribute("role") int role,
                                              @RequestParam(required = false) Integer userRole,
                                              @RequestParam(required = false) Integer status,
                                              @RequestParam(required = false) String keyword) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.users(userRole, status, keyword));
    }

    @PutMapping("/users/{id}/status")
    public ApiResponse<Void> updateUserStatus(@RequestAttribute("role") int role,
                                              @PathVariable long id,
                                              @RequestBody UserStatusRequest req) {
        requireAdmin(role);
        adminService.updateUserStatus(id, req.status());
        return ApiResponse.ok();
    }

    @GetMapping("/products")
    public ApiResponse<List<AdminProduct>> products(@RequestAttribute("role") int role,
                                                     @RequestParam(required = false) String keyword,
                                                     @RequestParam(required = false) Integer status) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.products(keyword, status));
    }

    @PutMapping("/products/{id}/status")
    public ApiResponse<Void> updateProductStatus(@RequestAttribute("role") int role,
                                                 @PathVariable long id,
                                                 @RequestBody ProductStatusRequest req) {
        requireAdmin(role);
        adminService.updateProductStatus(id, req.status());
        return ApiResponse.ok();
    }

    @DeleteMapping("/products/{id}")
    public ApiResponse<Void> deleteProduct(@RequestAttribute("role") int role, @PathVariable long id) {
        requireAdmin(role);
        adminService.deleteProduct(id);
        return ApiResponse.ok();
    }

    @GetMapping("/statistics/overview")
    public ApiResponse<AdminStatistics> statistics(@RequestAttribute("role") int role,
                                                   @RequestParam(defaultValue = "10") int hotLimit) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.statistics(hotLimit));
    }

    @GetMapping("/statistics/order-trend")
    public ApiResponse<List<AdminStatistics.TrendPoint>> orderTrend(@RequestAttribute("role") int role,
                                                                     @RequestParam(defaultValue = "7") int days) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.orderTrend(days));
    }

    @PostMapping("/employees")
    public ApiResponse<AdminEmployee> createEmployee(@RequestAttribute("role") int role,
                                                     @RequestBody EmployeeRequest req) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.createEmployee(req.username(), req.phone(), req.password()));
    }

    @PutMapping("/employees/{id}")
    public ApiResponse<AdminEmployee> updateEmployee(@RequestAttribute("role") int role,
                                                     @PathVariable long id,
                                                     @RequestBody EmployeeProfileRequest req) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.updateEmployee(id, req.username(), req.phone()));
    }

    @PutMapping("/employees/{id}/status")
    public ApiResponse<Void> updateEmployeeStatus(@RequestAttribute("role") int role,
                                                  @PathVariable long id,
                                                  @RequestBody EmployeeStatusRequest req) {
        requireAdmin(role);
        adminService.updateEmployeeStatus(id, req.status());
        return ApiResponse.ok();
    }

    // ============ 退款审批（演进项，见大纲 9.7） ============

    @GetMapping("/refunds")
    public ApiResponse<List<RefundRecord>> refunds(@RequestAttribute("role") int role,
                                                   @RequestParam(required = false) String status) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.refunds(status));
    }

    @GetMapping("/refunds/{id}")
    public ApiResponse<RefundRecord> refundDetail(@RequestAttribute("role") int role, @PathVariable long id) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.refundDetail(id));
    }

    @PostMapping("/refunds/{id}/approve")
    public ApiResponse<RefundRecord> approveRefund(@RequestAttribute("role") int role, @PathVariable long id) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.approveRefund(id));
    }

    @PostMapping("/refunds/{id}/reject")
    public ApiResponse<RefundRecord> rejectRefund(@RequestAttribute("role") int role, @PathVariable long id,
                                                  @RequestBody RefundRejectRequest req) {
        requireAdmin(role);
        return ApiResponse.ok(adminService.rejectRefund(id, req == null ? "" : req.rejectReason()));
    }

    private void requireAdmin(int role) {
        if (role != 2) {
            throw new BizException(403, "仅管理端可以执行该操作");
        }
    }

    public record CategoryRequest(String name, String icon, String color) {
    }

    public record StoreStatusRequest(int status) {
    }

    public record RefundRejectRequest(String rejectReason) {
    }

    public record EmployeeRequest(String username, String phone, String password) {
    }

    public record EmployeeProfileRequest(String username, String phone) {
    }

    public record EmployeeStatusRequest(int status) {
    }

    public record UserStatusRequest(int status) {
    }

    public record ProductStatusRequest(int status) {
    }
}
