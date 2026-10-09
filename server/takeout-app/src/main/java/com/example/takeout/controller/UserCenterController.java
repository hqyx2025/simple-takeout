package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.model.Address;
import com.example.takeout.model.BankCard;
import com.example.takeout.model.Coupon;
import com.example.takeout.model.Review;
import com.example.takeout.model.Store;
import com.example.takeout.service.UserCenterService;
import com.example.takeout.security.LoginRateLimiter;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
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

/**
 * 用户中心接口：优惠券、收藏、地址、店铺评价浏览、搜索（均需登录，与大纲第 7 章一致）
 */
@RestController
@RequestMapping("/api")
public class UserCenterController {

    private final UserCenterService service;
    private final LoginRateLimiter loginRateLimiter;

    @Autowired
    public UserCenterController(UserCenterService service, LoginRateLimiter loginRateLimiter) {
        this.service = service;
        this.loginRateLimiter = loginRateLimiter;
    }

    /** 兼容 standalone MVC 测试。 */
    public UserCenterController(UserCenterService service) {
        this(service, null);
    }

    // ============ 优惠券 ============

    @GetMapping("/coupons")
    public ApiResponse<List<Coupon>> coupons(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(service.listCoupons(userId));
    }

    @PostMapping("/coupons/claim")
    public ApiResponse<Coupon> claim(@RequestAttribute("userId") long userId,
                                     @RequestBody ClaimCouponRequest req) {
        return ApiResponse.ok(service.claimCoupon(userId, req.storeId(), req.name(), req.threshold(), req.amount()));
    }

    @GetMapping("/coupons/activities")
    public ApiResponse<List<UserCenterService.CouponActivity>> couponActivities(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(service.listCouponActivities());
    }

    // ============ 收藏 ============

    @GetMapping("/favorites")
    public ApiResponse<List<Store.StoreView>> favorites(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(service.listFavorites(userId));
    }

    @GetMapping("/favorites/status")
    public ApiResponse<Boolean> favoriteStatus(@RequestAttribute("userId") long userId,
                                               @RequestParam long storeId) {
        return ApiResponse.ok(service.isFavorited(userId, storeId));
    }

    @PostMapping("/favorites/toggle")
    public ApiResponse<Boolean> toggleFavorite(@RequestAttribute("userId") long userId,
                                               @RequestParam long storeId) {
        return ApiResponse.ok(service.toggleFavorite(userId, storeId));
    }

    // ============ 地址 ============

    @GetMapping("/addresses")
    public ApiResponse<List<Address>> addresses(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(service.listAddresses(userId));
    }

    @PostMapping("/addresses")
    public ApiResponse<Address> addAddress(@RequestAttribute("userId") long userId,
                                           @RequestBody AddressRequest req) {
        return ApiResponse.ok(service.addAddress(userId, req.name(), req.phone(), req.detail(), req.isDefault(),
                req.latitude(), req.longitude()));
    }

    @DeleteMapping("/addresses/{id}")
    public ApiResponse<Void> deleteAddress(@RequestAttribute("userId") long userId, @PathVariable long id) {
        service.deleteAddress(userId, id);
        return ApiResponse.ok();
    }

    @PutMapping("/addresses/{id}")
    public ApiResponse<Address> updateAddress(@RequestAttribute("userId") long userId,
                                              @PathVariable long id,
                                              @RequestBody AddressRequest req) {
        return ApiResponse.ok(service.updateAddress(userId, id, req.name(), req.phone(), req.detail(), req.isDefault(),
                req.latitude(), req.longitude()));
    }

    @PutMapping("/addresses/{id}/default")
    public ApiResponse<Void> setDefault(@RequestAttribute("userId") long userId, @PathVariable long id) {
        service.setDefaultAddress(userId, id);
        return ApiResponse.ok();
    }

    // ============ 钱包（已绑定银行卡） ============

    /** 钱包页展示的已绑定银行卡；余额走 /auth/me，保持单一权威口径。 */
    @GetMapping("/wallet/bank-cards")
    public ApiResponse<List<BankCard>> bankCards(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(service.listBankCards(userId));
    }

    @PostMapping("/wallet/bank-cards")
    public ApiResponse<BankCard> addBankCard(@RequestAttribute("userId") long userId,
                                            @RequestBody BankCardRequest request) {
        String cardNumber = request.fullCardNumber();
        // 旧客户端仅传尾号时保留兼容读取；新页面必须传完整卡号，完整卡号由服务端加密保存。
        if (cardNumber == null || cardNumber.isBlank()) {
            cardNumber = request.cardNoLast4();
            return ApiResponse.ok(service.addBankCard(userId, request.bankName(), request.cardType(), cardNumber));
        }
        return ApiResponse.ok(service.addBankCardFull(userId, request.bankName(), request.cardType(), cardNumber));
    }

    @DeleteMapping("/wallet/bank-cards/{id}")
    public ApiResponse<Void> deleteBankCard(@RequestAttribute("userId") long userId, @PathVariable long id) {
        service.deleteBankCard(userId, id);
        return ApiResponse.ok();
    }

    @PostMapping("/wallet/bank-cards/{id}/reveal")
    public ApiResponse<RevealedBankCard> revealBankCard(@RequestAttribute("userId") long userId,
                                                        @PathVariable long id,
                                                        @RequestBody RevealBankCardRequest request,
                                                        HttpServletRequest http,
                                                        HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("Pragma", "no-cache");
        String action = "bank-card-reveal";
        String identity = userId + ":" + LoginRateLimiter.clientIp(http);
        if (loginRateLimiter != null && loginRateLimiter.isBlocked(action, identity)) {
            throw new BizException(429, "支付密码尝试过于频繁，请稍后再试");
        }
        try {
            var result = new RevealedBankCard(service.revealBankCard(userId, id, request.paymentPassword()));
            if (loginRateLimiter != null) {
                loginRateLimiter.reset(action, identity);
            }
            return ApiResponse.ok(result);
        } catch (BizException e) {
            if (loginRateLimiter != null && ("支付密码不正确".equals(e.getMessage())
                    || "支付密码必须为 6 位数字".equals(e.getMessage()))) {
                loginRateLimiter.recordAttempt(action, identity);
            }
            throw e;
        }
    }

    // ============ 评价浏览 ============

    @GetMapping("/stores/{id}/reviews")
    public ApiResponse<List<Review.ReviewView>> storeReviews(@PathVariable long id) {
        return ApiResponse.ok(service.storeReviews(id));
    }

    @GetMapping("/goods/{id}/reviews")
    public ApiResponse<List<Review.ReviewView>> goodsReviews(@PathVariable long id) {
        return ApiResponse.ok(service.goodsReviews(id));
    }

    // ============ 商户评价管理 ============

    @GetMapping("/merchant/reviews")
    public ApiResponse<List<Review.ReviewView>> merchantReviews(@RequestAttribute("userId") long userId,
                                                                @RequestAttribute("role") int role) {
        requireMerchant(role);
        return ApiResponse.ok(service.merchantReviews(userId));
    }

    @PutMapping("/merchant/reviews/{id}/reply")
    public ApiResponse<Review.ReviewView> replyReview(@RequestAttribute("userId") long userId,
                                                      @RequestAttribute("role") int role,
                                                      @PathVariable long id,
                                                      @RequestBody ReplyRequest req) {
        requireMerchant(role);
        return ApiResponse.ok(service.replyReview(userId, id, req.reply()));
    }

    // ============ 搜索 ============

    @GetMapping("/search")
    public ApiResponse<List<Store.StoreView>> search(@RequestParam String keyword,
                                                     @RequestParam(required = false) Double latitude,
                                                     @RequestParam(required = false) Double longitude) {
        return ApiResponse.ok(service.search(keyword, latitude, longitude));
    }

    public record ClaimCouponRequest(long storeId, String name, double threshold, double amount) {
    }

    public record AddressRequest(String name, String phone, String detail, int isDefault,
                                 Double latitude, Double longitude) {
    }

    public record ReplyRequest(String reply) {
    }

    public record BankCardRequest(String bankName, String cardType,
                                  @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String fullCardNumber,
                                  @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String cardNoLast4) {
        @Override public String toString() {
            return "BankCardRequest[bankName=" + bankName + ", cardType=" + cardType + ", cardNumber=[redacted]]";
        }
    }

    public record RevealBankCardRequest(@JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String paymentPassword) {
        @Override public String toString() { return "RevealBankCardRequest[paymentPassword=[redacted]]"; }
    }

    public record RevealedBankCard(String cardNumber) {
        @Override public String toString() { return "RevealedBankCard[cardNumber=[redacted]]"; }
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Void>> invalidBody() {
        // Jackson 解析错误可能包含卡号或支付密码，不交给记录异常文本的全局处理器。
        return ResponseEntity.badRequest().body(ApiResponse.error(400, "请求参数格式不正确"));
    }

    private void requireMerchant(int role) {
        if (role != 1) {
            throw new com.example.takeout.common.BizException(403, "仅商户可以执行该操作");
        }
    }
}
