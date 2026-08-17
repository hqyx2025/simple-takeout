package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.model.Address;
import com.example.takeout.model.Coupon;
import com.example.takeout.model.Review;
import com.example.takeout.model.Store;
import com.example.takeout.service.UserCenterService;
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

    public UserCenterController(UserCenterService service) {
        this.service = service;
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
        return ApiResponse.ok(service.addAddress(userId, req.name(), req.phone(), req.detail(), req.isDefault()));
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
        return ApiResponse.ok(service.updateAddress(userId, id, req.name(), req.phone(), req.detail(), req.isDefault()));
    }

    @PutMapping("/addresses/{id}/default")
    public ApiResponse<Void> setDefault(@RequestAttribute("userId") long userId, @PathVariable long id) {
        service.setDefaultAddress(userId, id);
        return ApiResponse.ok();
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

    // ============ 搜索 ============

    @GetMapping("/search")
    public ApiResponse<List<Store.StoreView>> search(@RequestParam String keyword) {
        return ApiResponse.ok(service.search(keyword));
    }

    public record ClaimCouponRequest(long storeId, String name, double threshold, double amount) {
    }

    public record AddressRequest(String name, String phone, String detail, int isDefault) {
    }
}
