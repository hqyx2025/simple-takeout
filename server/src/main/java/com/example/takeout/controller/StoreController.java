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
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 店铺/商品/分类接口
 * 所有接口均需登录（WebConfig 全量拦截，与大纲第 7 章"浏览也需登录"一致）；商户管理类接口由 ownerId 校验归属
 */
@RestController
@RequestMapping("/api")
public class StoreController {

    private static final Logger log = LoggerFactory.getLogger(StoreController.class);

    private final StoreService storeService;

    public StoreController(StoreService storeService) {
        this.storeService = storeService;
    }

    @GetMapping("/categories")
    public ApiResponse<List<Category>> categories() {
        List<Category> categories = storeService.listCategories();
        log.info("[数据] 分类查询返回 count={} items={}", categories.size(),
                categories.stream().map(c -> c.id() + ":" + c.name()).collect(Collectors.joining(",")));
        return ApiResponse.ok(categories);
    }

    @GetMapping("/stores")
    public ApiResponse<List<Store.StoreView>> stores(@RequestParam(required = false) Integer categoryId) {
        List<Store.StoreView> stores = storeService.listStores(categoryId);
        log.info("[数据] 店铺查询 categoryId={} 返回 count={} items={}", categoryId,
                stores.size(), stores.stream().map(s -> s.id() + ":" + s.name() + ":cat=" + s.categoryId())
                        .collect(Collectors.joining(",")));
        return ApiResponse.ok(stores);
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
    public ApiResponse<List<Store.StoreView>> myStores(@RequestAttribute("userId") long userId,
                                                       @RequestAttribute("role") int role) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.merchantStores(userId));
    }

    @GetMapping("/merchant/stores/{storeId}/goods")
    public ApiResponse<List<Goods>> merchantGoods(@RequestAttribute("userId") long userId,
                                                  @RequestAttribute("role") int role,
                                                  @PathVariable long storeId) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.merchantGoods(userId, storeId));
    }

    @PostMapping("/merchant/stores")
    public ApiResponse<Store.StoreView> createStore(@RequestAttribute("userId") long userId,
                                                    @RequestAttribute("role") int role,
                                                    @RequestBody CreateStoreRequest req) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.createStore(userId, req.name(), req.categoryId(),
                req.deliveryFee(), req.minOrder(), req.deliveryTime(), req.notice()));
    }

    @PutMapping("/merchant/stores/{storeId}")
    public ApiResponse<Store.StoreView> updateStore(@RequestAttribute("userId") long userId,
                                                    @RequestAttribute("role") int role,
                                                    @PathVariable long storeId,
                                                    @RequestBody StoreService.StorePatch patch) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.updateStore(userId, storeId, patch));
    }

    @PostMapping("/merchant/stores/{storeId}/goods")
    public ApiResponse<Goods> addGoods(@RequestAttribute("userId") long userId,
                                       @RequestAttribute("role") int role,
                                       @PathVariable long storeId,
                                       @RequestBody StoreService.GoodsInput input) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.addGoods(userId, storeId, input));
    }

    @PutMapping("/merchant/goods/{goodsId}")
    public ApiResponse<Goods> updateGoods(@RequestAttribute("userId") long userId,
                                          @RequestAttribute("role") int role,
                                          @PathVariable long goodsId,
                                          @RequestBody StoreService.GoodsInput input) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.updateGoods(userId, goodsId, input));
    }

    @DeleteMapping("/merchant/goods/{goodsId}")
    public ApiResponse<Void> deleteGoods(@RequestAttribute("userId") long userId,
                                         @RequestAttribute("role") int role,
                                         @PathVariable long goodsId) {
        requireMerchant(role);
        storeService.deleteGoods(userId, goodsId);
        return ApiResponse.ok();
    }

    public record CreateStoreRequest(String name, int categoryId, double deliveryFee,
                                     double minOrder, String deliveryTime, String notice) {
    }

    private void requireMerchant(int role) {
        if (role != 1) {
            throw new com.example.takeout.common.BizException(403, "仅商户可以执行该操作");
        }
    }
}
