package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.model.Category;
import com.example.takeout.model.Goods;
import com.example.takeout.model.GoodsSpec;
import com.example.takeout.model.MarketingActivity;
import com.example.takeout.model.Seckill;
import com.example.takeout.model.Setmeal;
import com.example.takeout.model.Store;
import com.example.takeout.model.SpecialGoods;
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

    @GetMapping("/stores/{storeId}/activities")
    public ApiResponse<List<MarketingActivity>> storeActivities(@PathVariable long storeId) {
        return ApiResponse.ok(storeService.listStoreActivities(storeId));
    }

    @GetMapping("/stores/{storeId}/setmeals")
    public ApiResponse<List<Setmeal>> storeSetmeals(@PathVariable long storeId) {
        return ApiResponse.ok(storeService.listStoreSetmeals(storeId));
    }

    @GetMapping("/merchant/setmeals")
    public ApiResponse<List<Setmeal>> merchantSetmeals(@RequestAttribute("userId") long userId,
                                                       @RequestAttribute("role") int role,
                                                       @RequestParam long storeId) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.listMerchantSetmeals(userId, storeId));
    }

    @PostMapping("/merchant/setmeals")
    public ApiResponse<Setmeal> createSetmeal(@RequestAttribute("userId") long userId,
                                              @RequestAttribute("role") int role,
                                              @RequestParam long storeId,
                                              @RequestBody StoreService.SetmealInput input) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.createSetmeal(userId, storeId, input));
    }

    @DeleteMapping("/merchant/setmeals/{setmealId}")
    public ApiResponse<Void> deleteSetmeal(@RequestAttribute("userId") long userId,
                                           @RequestAttribute("role") int role,
                                           @RequestParam long storeId,
                                           @PathVariable long setmealId) {
        requireMerchant(role);
        storeService.deleteMerchantSetmeal(userId, storeId, setmealId);
        return ApiResponse.ok();
    }

    @GetMapping("/merchant/employees")
    public ApiResponse<List<com.example.takeout.model.Employee>> merchantEmployees(@RequestAttribute("userId") long userId,
                                                                                   @RequestAttribute("role") int role,
                                                                                   @RequestParam long storeId) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.listStoreEmployees(userId, storeId));
    }

    @PostMapping("/merchant/employees")
    public ApiResponse<com.example.takeout.model.Employee> addEmployee(@RequestAttribute("userId") long userId,
                                                                       @RequestAttribute("role") int role,
                                                                       @RequestParam long storeId,
                                                                       @RequestBody EmployeeBody req) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.addStoreEmployee(userId, storeId, req.userId(), req.roleName()));
    }

    @DeleteMapping("/merchant/employees/{employeeId}")
    public ApiResponse<Void> removeEmployee(@RequestAttribute("userId") long userId,
                                            @RequestAttribute("role") int role,
                                            @RequestParam long storeId,
                                            @PathVariable long employeeId) {
        requireMerchant(role);
        storeService.removeStoreEmployee(userId, storeId, employeeId);
        return ApiResponse.ok();
    }

    public record EmployeeBody(long userId, String roleName) {
    }

    @GetMapping("/stores")
    public ApiResponse<List<Store.StoreView>> stores(@RequestParam(required = false) Integer categoryId,
                                                     @RequestParam(required = false) Double latitude,
                                                     @RequestParam(required = false) Double longitude) {
        List<Store.StoreView> stores = storeService.listStores(categoryId, latitude, longitude);
        log.info("[数据] 店铺查询 categoryId={} 返回 count={} items={}", categoryId,
                stores.size(), stores.stream().map(s -> s.id() + ":" + s.name() + ":cat=" + s.categoryId())
                        .collect(Collectors.joining(",")));
        return ApiResponse.ok(stores);
    }

    @GetMapping("/stores/recommended")
    public ApiResponse<List<Store.StoreView>> recommendedStores(
            @RequestParam(defaultValue = "2") double maxDistanceKm,
            @RequestParam(defaultValue = "10") int limit,
            @RequestParam(required = false) Double latitude,
            @RequestParam(required = false) Double longitude) {
        return ApiResponse.ok(storeService.recommendedStores(maxDistanceKm, limit, latitude, longitude));
    }

    @GetMapping("/stores/{id}")
    public ApiResponse<Store.StoreView> storeDetail(@PathVariable long id) {
        return ApiResponse.ok(storeService.storeDetail(id));
    }

    @GetMapping("/stores/{id}/goods")
    public ApiResponse<List<Goods>> goods(@PathVariable long id) {
        return ApiResponse.ok(storeService.listGoods(id));
    }

    @GetMapping("/goods/special")
    public ApiResponse<List<SpecialGoods>> specialGoods(
            @RequestParam(defaultValue = "10") int limit,
            @RequestParam(required = false) Double latitude,
            @RequestParam(required = false) Double longitude) {
        return ApiResponse.ok(storeService.listSpecialGoods(limit, latitude, longitude));
    }

    // ============ 营销：榜单 / 限时秒杀 / 凑单 ============

    /** 店铺榜。 */
    @GetMapping("/rankings/stores")
    public ApiResponse<List<Store.StoreView>> rankStores(
            @RequestParam(defaultValue = "10") int limit,
            @RequestParam(required = false) Double latitude,
            @RequestParam(required = false) Double longitude) {
        return ApiResponse.ok(storeService.rankStores(limit, latitude, longitude));
    }

    /** 菜品榜（热销榜）。 */
    @GetMapping("/rankings/goods")
    public ApiResponse<List<SpecialGoods>> rankGoods(
            @RequestParam(defaultValue = "10") int limit,
            @RequestParam(required = false) Double latitude,
            @RequestParam(required = false) Double longitude) {
        return ApiResponse.ok(storeService.rankGoods(limit, latitude, longitude));
    }

    /** 首页限时秒杀。 */
    @GetMapping("/seckills")
    public ApiResponse<List<Seckill.SeckillView>> seckills(
            @RequestParam(defaultValue = "6") int limit,
            @RequestParam(required = false) Double latitude,
            @RequestParam(required = false) Double longitude) {
        return ApiResponse.ok(storeService.listSeckills(limit, latitude, longitude));
    }

    /** 凑单提示：还差多少钱起送 + 店内可凑单菜品。 */
    @GetMapping("/stores/{id}/bundle")
    public ApiResponse<StoreService.BundleView> bundle(@PathVariable long id,
                                                       @RequestParam(defaultValue = "0") double amount) {
        return ApiResponse.ok(storeService.bundle(id, amount));
    }

    /** 用户端：店铺详情展示的店内商户分类（与商品 merchantCategoryId 对应）。 */
    @GetMapping("/stores/{id}/categories")
    public ApiResponse<List<Category>> storeMerchantCategories(@PathVariable long id) {
        return ApiResponse.ok(storeService.publicMerchantCategories(id));
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
                req.deliveryFee(), req.minOrder(), req.deliveryTime(), req.notice(),
                req.address(), req.latitude(), req.longitude(), req.deliveryRadius()));
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

    @PutMapping("/merchant/goods/{goodsId}/stock")
    public ApiResponse<Goods> updateStock(@RequestAttribute("userId") long userId,
                                          @RequestAttribute("role") int role,
                                          @PathVariable long goodsId,
                                          @RequestBody StockRequest req) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.updateStock(userId, goodsId, req.stock()));
    }

    // ============ 多规格 SKU ============

    @GetMapping("/merchant/goods/{goodsId}/specs")
    public ApiResponse<List<GoodsSpec>> goodsSpecs(@RequestAttribute("userId") long userId,
                                                   @RequestAttribute("role") int role,
                                                   @PathVariable long goodsId) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.listSpecs(userId, goodsId));
    }

    @PutMapping("/merchant/goods/{goodsId}/specs")
    public ApiResponse<Goods> updateGoodsSpecs(@RequestAttribute("userId") long userId,
                                               @RequestAttribute("role") int role,
                                               @PathVariable long goodsId,
                                               @RequestBody GoodsSpecsRequest req) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.updateSpecs(userId, goodsId,
                req.specs() == null ? List.of() : req.specs()));
    }

    // ============ 商户分类（演进项，见大纲 8.3） ============

    @GetMapping("/merchant/categories")
    public ApiResponse<List<Category>> merchantCategories(@RequestAttribute("userId") long userId,
                                                          @RequestAttribute("role") int role) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.merchantCategories(userId));
    }

    @PostMapping("/merchant/categories")
    public ApiResponse<Category> createMerchantCategory(@RequestAttribute("userId") long userId,
                                                        @RequestAttribute("role") int role,
                                                        @RequestBody MerchantCategoryRequest req) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.createMerchantCategory(userId, req.name(), req.sort()));
    }

    @PutMapping("/merchant/categories/{categoryId}")
    public ApiResponse<Category> updateMerchantCategory(@RequestAttribute("userId") long userId,
                                                        @RequestAttribute("role") int role,
                                                        @PathVariable long categoryId,
                                                        @RequestBody MerchantCategoryRequest req) {
        requireMerchant(role);
        return ApiResponse.ok(storeService.updateMerchantCategory(userId, categoryId, req.name(), req.sort()));
    }

    @DeleteMapping("/merchant/categories/{categoryId}")
    public ApiResponse<Void> deleteMerchantCategory(@RequestAttribute("userId") long userId,
                                                    @RequestAttribute("role") int role,
                                                    @PathVariable long categoryId) {
        requireMerchant(role);
        storeService.deleteMerchantCategory(userId, categoryId);
        return ApiResponse.ok();
    }

    public record CreateStoreRequest(String name, int categoryId, double deliveryFee,
                                     double minOrder, String deliveryTime, String notice,
                                     String address, Double latitude, Double longitude,
                                     int deliveryRadius) {
    }

    public record StockRequest(int stock) {
    }

    public record MerchantCategoryRequest(String name, int sort) {
    }

    /** 多规格整体覆盖提交（id=0 表示新增规格）。 */
    public record GoodsSpecsRequest(List<StoreService.SpecInput> specs) {
    }

    private void requireMerchant(int role) {
        if (role != 1) {
            throw new com.example.takeout.common.BizException(403, "仅商户可以执行该操作");
        }
    }
}
