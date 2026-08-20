package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.model.Order;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.model.Review;
import com.example.takeout.service.OrderService;
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

/**
 * 订单接口：用户下单/查单/取消/确认收货/评价；商户接单/出餐/完成；商户统计
 */
@RestController
@RequestMapping("/api")
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    // ============ 用户端 ============

    @PostMapping("/orders")
    public ApiResponse<Order.OrderView> createOrder(@RequestAttribute("userId") long userId,
                                                    @RequestBody CreateOrderRequest req) {
        return ApiResponse.ok(orderService.createOrder(userId, req.storeId(), req.items(),
                req.addressId(), req.couponId(), req.remark(), req.checkoutGoodsIds()));
    }

    @GetMapping("/orders")
    public ApiResponse<List<Order.OrderView>> userOrders(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(orderService.userOrders(userId));
    }

    @GetMapping("/orders/{id}")
    public ApiResponse<Order.OrderView> orderDetail(@RequestAttribute("userId") long userId,
                                                    @RequestAttribute("role") int role,
                                                    @PathVariable long id) {
        return ApiResponse.ok(orderService.orderDetail(userId, role, id));
    }

    @PutMapping("/orders/{id}/cancel")
    public ApiResponse<Order.OrderView> cancel(@RequestAttribute("userId") long userId, @PathVariable long id) {
        return ApiResponse.ok(orderService.cancelOrder(userId, id));
    }

    @PutMapping("/orders/{id}/confirm")
    public ApiResponse<Order.OrderView> confirm(@RequestAttribute("userId") long userId, @PathVariable long id) {
        return ApiResponse.ok(orderService.confirmOrder(userId, id));
    }

    @PostMapping("/orders/{id}/review")
    public ApiResponse<Review> review(@RequestAttribute("userId") long userId, @PathVariable long id,
                                      @RequestBody ReviewRequest req) {
        return ApiResponse.ok(orderService.reviewOrder(userId, id, req.goodsId(), req.rating(), req.content(), req.tags()));
    }

    @PostMapping("/orders/{id}/refund")
    public ApiResponse<RefundRecord> refund(@RequestAttribute("userId") long userId, @PathVariable long id,
                                            @RequestBody(required = false) RefundRequest req) {
        String reason = req == null ? "" : req.reason();
        return ApiResponse.ok(orderService.applyRefund(userId, id, reason));
    }

    // ============ 商户端 ============

    @GetMapping("/merchant/orders")
    public ApiResponse<List<Order.OrderView>> merchantOrders(@RequestAttribute("userId") long userId,
                                                             @RequestAttribute("role") int role) {
        requireMerchant(role);
        return ApiResponse.ok(orderService.merchantOrders(userId));
    }

    @PutMapping("/merchant/orders/{id}/{action}")
    public ApiResponse<Order.OrderView> merchantFlow(@RequestAttribute("userId") long userId,
                                                     @RequestAttribute("role") int role,
                                                     @PathVariable long id,
                                                     @PathVariable String action) {
        requireMerchant(role);
        return ApiResponse.ok(orderService.merchantFlow(userId, id, action));
    }

    @GetMapping("/merchant/stats")
    public ApiResponse<OrderService.MerchantStats> stats(@RequestAttribute("userId") long userId,
                                                         @RequestAttribute("role") int role,
                                                         @RequestParam(defaultValue = "0") long storeId,
                                                         @RequestParam(defaultValue = "week") String range) {
        requireMerchant(role);
        return ApiResponse.ok(orderService.merchantStats(userId, storeId, range));
    }

    public record CreateOrderRequest(long storeId, List<Order.OrderItem> items, long addressId,
                                     long couponId, String remark, List<Long> checkoutGoodsIds) {
    }

    public record ReviewRequest(long goodsId, int rating, String content, List<String> tags) {
    }

    public record RefundRequest(String reason) {
    }

    private void requireMerchant(int role) {
        if (role != 1) {
            throw new com.example.takeout.common.BizException(403, "仅商户可以执行该操作");
        }
    }
}
