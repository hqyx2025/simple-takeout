package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.model.Order;
import com.example.takeout.model.SetmealOrder;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.model.Review;
import com.example.takeout.security.LoginRateLimiter;
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
import com.fasterxml.jackson.annotation.JsonProperty;
import com.example.takeout.service.thirdparty.PaymentChannels;

import java.util.List;

/**
 * 订单接口：用户下单/查单/取消/确认收货/评价；商户接单/出餐/完成；商户统计
 */
@RestController
@RequestMapping("/api")
public class OrderController {

    private final OrderService orderService;
    private final LoginRateLimiter orderRateLimiter;

    public OrderController(OrderService orderService, LoginRateLimiter orderRateLimiter) {
        this.orderService = orderService;
        this.orderRateLimiter = orderRateLimiter;
    }

    // ============ 用户端 ============

    @PostMapping("/orders")
    public ApiResponse<Order.OrderView> createOrder(@RequestAttribute("userId") long userId,
                                                    @RequestBody CreateOrderRequest req) {
        // 下单按账号限流；Redis 不可用时由本地窗口继续保护。
        if (orderRateLimiter.isBlocked("order", "u" + userId)) {
            throw new BizException(429, "下单过于频繁，请稍后再试");
        }
        orderRateLimiter.recordAttempt("order", "u" + userId);
        return ApiResponse.ok(orderService.createOrder(userId, req.storeId(), req.items(),
                req.addressId(), req.couponId(), req.remark(), req.checkoutGoodsIds(), req.expectTime(),
                req.idempotencyKey(), req.setmeals(), req.deliveryType()));
    }

    @GetMapping("/orders")
    public ApiResponse<List<Order.OrderView>> userOrders(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(orderService.userOrders(userId));
    }

    @GetMapping("/orders/page")
    public ApiResponse<OrderService.OrderPage> userOrdersPage(@RequestAttribute("userId") long userId,
                                                              @RequestParam(required = false) Integer status,
                                                              @RequestParam(defaultValue = "1") int page,
                                                              @RequestParam(defaultValue = "30") int pageSize) {
        return ApiResponse.ok(orderService.userOrders(userId, status, page, pageSize));
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

    /** BALANCE 同步扣款；ALIPAY/WECHAT 只创建预支付，支付结果由验签通知确认。 */
    @PostMapping("/orders/{id}/pay")
    public ApiResponse<Order.OrderView> pay(@RequestAttribute("userId") long userId, @PathVariable long id,
                                            @RequestParam String channel,
                                            @RequestParam(defaultValue = "QR") String mode,
                                            @RequestBody(required = false) PaymentRequest request) {
        if (!PaymentChannels.BALANCE.equals(PaymentChannels.normalize(channel))) {
            return ApiResponse.ok(orderService.payOrder(userId, id, channel, mode));
        }
        String identity = "u" + userId;
        if (orderRateLimiter.isBlocked("payment-password", identity)) {
            throw new BizException(429, "支付密码尝试过于频繁，请稍后再试");
        }
        orderRateLimiter.recordAttempt("payment-password", identity);
        Order.OrderView result = orderService.payOrder(userId, id, channel, mode,
                request == null ? null : request.paymentPassword());
        orderRateLimiter.reset("payment-password", identity);
        return ApiResponse.ok(result);
    }

    public record PaymentRequest(@JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String paymentPassword) {
        @Override public String toString() { return "PaymentRequest[redacted]"; }
    }

    @PostMapping("/orders/{id}/payment/query")
    public ApiResponse<Order.OrderView> queryPayment(@RequestAttribute("userId") long userId,
                                                    @PathVariable long id) {
        if (orderRateLimiter.isBlocked("payment-query", "u" + userId)) {
            throw new BizException(429, "支付查询过于频繁，请稍后再试");
        }
        orderRateLimiter.recordAttempt("payment-query", "u" + userId);
        return ApiResponse.ok(orderService.refreshPaymentStatus(userId, id));
    }

    @PutMapping("/orders/{id}/confirm")
    public ApiResponse<Order.OrderView> confirm(@RequestAttribute("userId") long userId, @PathVariable long id) {
        return ApiResponse.ok(orderService.confirmOrder(userId, id));
    }

    @PostMapping("/orders/{id}/review")
    public ApiResponse<Review> review(@RequestAttribute("userId") long userId, @PathVariable long id,
                                      @RequestBody ReviewRequest req) {
        return ApiResponse.ok(orderService.reviewOrder(userId, id, req.goodsId(), req.rating(), req.content(),
                req.tags(), req.images(), req.anonymous()));
    }

    @PostMapping("/orders/{id}/refund")
    public ApiResponse<RefundRecord> refund(@RequestAttribute("userId") long userId,
                                            @RequestAttribute("role") int role, @PathVariable long id,
                                            @RequestBody(required = false) RefundRequest req) {
        requireCustomer(role);
        String reasonType = req == null ? null : req.reasonType();
        String reason = req == null ? "" : req.reason();
        return ApiResponse.ok(orderService.applyRefund(userId, id, reasonType, reason,
                req == null ? null : req.idempotencyKey(), req == null ? null : req.amount(),
                req == null ? List.of() : req.evidenceImages()));
    }

    @GetMapping("/orders/{id}/refunds")
    public ApiResponse<List<RefundRecord>> refunds(@RequestAttribute("userId") long userId,
                                                  @RequestAttribute("role") int role, @PathVariable long id) {
        requireCustomer(role);
        return ApiResponse.ok(orderService.refundHistory(userId, id));
    }

    @PostMapping("/orders/{id}/refunds/{refundId}/appeal")
    public ApiResponse<RefundRecord> appeal(@RequestAttribute("userId") long userId,
                                            @RequestAttribute("role") int role, @PathVariable long id,
                                            @PathVariable long refundId, @RequestBody AppealRequest req) {
        requireCustomer(role);
        return ApiResponse.ok(orderService.appealRefund(userId, id, refundId, req.reason(), req.evidenceImages()));
    }

    public record AppealRequest(String reason, List<String> evidenceImages) {}

    // ============ 商户端 ============

    @GetMapping("/merchant/orders")
    public ApiResponse<List<Order.OrderView>> merchantOrders(@RequestAttribute("userId") long userId,
                                                             @RequestAttribute("role") int role) {
        requireMerchant(role);
        return ApiResponse.ok(orderService.merchantOrders(userId));
    }

    @GetMapping("/merchant/orders/page")
    public ApiResponse<OrderService.OrderPage> merchantOrdersPage(@RequestAttribute("userId") long userId,
                                                                  @RequestAttribute("role") int role,
                                                                  @RequestParam(required = false) Integer status,
                                                                  @RequestParam(defaultValue = "1") int page,
                                                                  @RequestParam(defaultValue = "30") int pageSize) {
        requireMerchant(role);
        return ApiResponse.ok(orderService.merchantOrders(userId, status, page, pageSize));
    }

    @PutMapping("/merchant/orders/{id}/{action}")
    public ApiResponse<Order.OrderView> merchantFlow(@RequestAttribute("userId") long userId,
                                                     @RequestAttribute("role") int role,
                                                     @PathVariable long id,
                                                     @PathVariable String action) {
        requireMerchant(role);
        return ApiResponse.ok(orderService.merchantFlow(userId, id, action));
    }

    @PostMapping("/merchant/orders/{id}/reject")
    public ApiResponse<Order.OrderView> merchantReject(@RequestAttribute("userId") long userId,
                                                       @RequestAttribute("role") int role,
                                                       @PathVariable long id,
                                                       @RequestBody(required = false) MerchantRejectRequest req) {
        requireMerchant(role);
        return ApiResponse.ok(orderService.merchantReject(userId, id,
                req == null ? null : req.reasonCode(), req == null ? null : req.note(),
                req == null ? null : req.goodsId(), req == null ? null : req.specId()));
    }

    @GetMapping("/merchant/stats")
    public ApiResponse<OrderService.MerchantStats> stats(@RequestAttribute("userId") long userId,
                                                         @RequestAttribute("role") int role,
                                                         @RequestParam(defaultValue = "0") long storeId) {
        requireMerchant(role);
        return ApiResponse.ok(orderService.merchantStats(userId, storeId));
    }

    /** idempotencyKey：客户端为每次下单意图生成的一次性 UUID，服务端 Redis SET NX 防连点/重放；旧客户端不传则跳过校验。 */
    public record CreateOrderRequest(long storeId, List<Order.OrderItem> items, long addressId,
                                     long couponId, String remark, List<Long> checkoutGoodsIds,
                                     String expectTime, String idempotencyKey,
                                     List<SetmealOrder> setmeals, String deliveryType) {
    }

    public record ReviewRequest(long goodsId, int rating, String content, List<String> tags,
                                List<String> images, int anonymous) {
    }

    public record RefundRequest(String reasonType, String reason, String idempotencyKey,
                                java.math.BigDecimal amount, List<String> evidenceImages) {
    }

    public record MerchantRejectRequest(String reasonCode, String note, Long goodsId, Long specId) {
    }

    private void requireMerchant(int role) {
        if (role != 1) {
            throw new com.example.takeout.common.BizException(403, "仅商户可以执行该操作");
        }
    }

    private void requireCustomer(int role) {
        if (role != 0) throw new BizException(403, "仅用户可以操作退款申请");
    }
}
