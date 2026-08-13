package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.model.Category;
import com.example.takeout.model.Goods;
import com.example.takeout.model.Store;
import com.example.takeout.service.StoreService;
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
 * 店铺/商品/分类接口
 * 浏览类接口放行游客；管理类接口需登录（商户身份由 ownerId 校验）
 */
@RestController
@RequestMapping("/api")
public class StoreController {

    private final StoreService storeService;

    public StoreController(StoreService storeService) {
        this.storeService = storeService;
    }

    @GetMapping("/categories")
    public ApiResponse<List<Category>> categories() {
        return ApiResponse.ok(storeService.listCategories());
    }

    @GetMapping("/stores")
    public ApiResponse<List<Store.StoreView>> stores(@RequestParam(required = false) Integer categoryId) {
        return ApiResponse.ok(storeService.listStores(categoryId));
    }

    @GetMapping("/stores/{id}")
    public ApiResponse<Store.StoreView> storeDetail(@PathVariable long id) {
        return ApiResponse.ok(storeService.storeDetail(id));
    }

    @GetMapping("/stores/{id}/goods")
    public ApiResponse<List<Goods>> goods(@PathVariable long id) {
        return ApiResponse.ok(storeService.listGoods(id));
    }

    @GetMapping("/merchant/stores")
    public ApiResponse<List<Store.StoreView>> myStores(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(storeService.merchantStores(userId));
    }

    @GetMapping("/merchant/stores/{storeId}/goods")
    public ApiResponse<List<Goods>> merchantGoods(@RequestAttribute("userId") long userId,
                                                  @PathVariable long storeId) {
        return ApiResponse.ok(storeService.merchantGoods(userId, storeId));
    }

    @PostMapping("/merchant/stores")
    public ApiResponse<Store.StoreView> createStore(@RequestAttribute("userId") long userId,
                                                    @RequestBody CreateStoreRequest req) {
        return ApiResponse.ok(storeService.createStore(userId, req.name(), req.categoryId(),
                req.deliveryFee(), req.minOrder(), req.deliveryTime(), req.notice()));
    }

    @PutMapping("/merchant/stores/{storeId}")
    public ApiResponse<Store.StoreView> updateStore(@RequestAttribute("userId") long userId,
                                                    @PathVariable long storeId,
                                                    @RequestBody StoreService.StorePatch patch) {
        return ApiResponse.ok(storeService.updateStore(userId, storeId, patch));
    }

    @PostMapping("/merchant/stores/{storeId}/goods")
    public ApiResponse<Goods> addGoods(@RequestAttribute("userId") long userId,
                                       @PathVariable long storeId,
                                       @RequestBody StoreService.GoodsInput input) {
        return ApiResponse.ok(storeService.addGoods(userId, storeId, input));
    }

    @PutMapping("/merchant/goods/{goodsId}")
    public ApiResponse<Goods> updateGoods(@RequestAttribute("userId") long userId,
                                          @PathVariable long goodsId,
                                          @RequestBody StoreService.GoodsInput input) {
        return ApiResponse.ok(storeService.updateGoods(userId, goodsId, input));
    }

    @DeleteMapping("/merchant/goods/{goodsId}")
    public ApiResponse<Void> deleteGoods(@RequestAttribute("userId") long userId,
                                         @PathVariable long goodsId) {
        storeService.deleteGoods(userId, goodsId);
        return ApiResponse.ok();
    }

    public record CreateStoreRequest(String name, int categoryId, double deliveryFee,
                                     double minOrder, String deliveryTime, String notice) {
    }
}
