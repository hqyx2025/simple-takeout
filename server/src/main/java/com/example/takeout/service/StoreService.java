package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.model.Category;
import com.example.takeout.model.Goods;
import com.example.takeout.model.Store;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Set;

/**
 * 店铺与商品服务：浏览、商户管理
 */
@Service
public class StoreService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final StoreDao storeDao;
    private final GoodsDao goodsDao;
    private final ObjectMapper objectMapper;

    public StoreService(StoreDao storeDao, GoodsDao goodsDao, ObjectMapper objectMapper) {
        this.storeDao = storeDao;
        this.goodsDao = goodsDao;
        this.objectMapper = objectMapper;
    }

    public List<Category> listCategories() {
        return storeDao.listCategories();
    }

    public List<Store.StoreView> listStores(Integer categoryId) {
        if (categoryId != null && categoryId < 0) {
            throw new BizException("分类参数不合法");
        }
        if (categoryId != null && categoryId > 0 && !storeDao.categoryExists(categoryId)) {
            throw new BizException(404, "分类不存在");
        }
        List<Store> stores = categoryId == null || categoryId == 0
                ? storeDao.listAll()
                : storeDao.listByCategory(categoryId);
        return stores.stream().map(this::toView).toList();
    }

    public Store.StoreView storeDetail(long id) {
        Store store = storeDao.findById(id).orElseThrow(() -> new BizException("店铺不存在"));
        return toView(store);
    }

    public List<Goods> listGoods(long storeId) {
        storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        return goodsDao.listByStore(storeId);
    }

    public List<Store.StoreView> merchantStores(long ownerId) {
        return storeDao.listByOwner(ownerId).stream().map(this::toView).toList();
    }

    public List<Goods> merchantGoods(long ownerId, long storeId) {
        requireOwned(ownerId, storeId);
        return goodsDao.listByStoreAll(storeId);
    }

    public Store.StoreView createStore(long ownerId, String name, int categoryId, double deliveryFee,
                                       double minOrder, String deliveryTime, String notice) {
        if (name == null || name.isBlank()) {
            throw new BizException("店铺名称不能为空");
        }
        validateCategory(categoryId);
        if (!Double.isFinite(deliveryFee) || deliveryFee < 0 || !Double.isFinite(minOrder) || minOrder < 0) {
            throw new BizException("配送费和起送价必须为非负数字");
        }
        String now = LocalDateTime.now().format(FMT);
        Store store = new Store(0, name, "", 4.5, 0, deliveryFee, minOrder,
                deliveryTime == null || deliveryTime.isBlank() ? "30分钟" : deliveryTime,
                "1.0km", "[\"新店特惠\"]", notice == null ? "" : notice,
                categoryId, "[" + categoryId + "]", ownerId, 1, now);
        long id = storeDao.insert(store);
        return storeDetail(id);
    }

    public Store.StoreView updateStore(long ownerId, long storeId, StorePatch patch) {
        Store store = requireOwned(ownerId, storeId);
        Store updated = new Store(store.id(), patch.name() == null ? store.name() : patch.name(),
                store.image(), store.rating(), store.monthlySales(),
                patch.deliveryFee() < 0 ? store.deliveryFee() : patch.deliveryFee(),
                patch.minOrder() < 0 ? store.minOrder() : patch.minOrder(),
                patch.deliveryTime() == null ? store.deliveryTime() : patch.deliveryTime(),
                store.distance(), store.tags(), patch.notice() == null ? store.notice() : patch.notice(),
                store.categoryId(), store.categoryIds(), store.ownerId(),
                patch.status() < 0 ? store.status() : patch.status(), store.createTime());
        storeDao.update(updated);
        return storeDetail(storeId);
    }

    public Goods addGoods(long ownerId, long storeId, GoodsInput input) {
        requireOwned(ownerId, storeId);
        validateGoodsInput(input);
        validateCategory(input.categoryId());
        validateMerchantCategory(ownerId, input.merchantCategoryId());
        String now = LocalDateTime.now().format(FMT);
        Goods goods = new Goods(0, storeId, input.name(), input.description(),
                input.price(), input.originalPrice(), input.image(), input.categoryId(),
                input.merchantCategoryId(), input.stock(), 0, 0, 4.5,
                input.tag() == null ? "" : input.tag(), 1, now);
        long id = goodsDao.insert(goods);
        return goodsDao.findById(id).orElseThrow(() -> new BizException("商品创建失败"));
    }

    public Goods updateGoods(long ownerId, long goodsId, GoodsInput input) {
        Goods goods = goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品不存在"));
        requireOwned(ownerId, goods.storeId());
        validateGoodsInput(input);
        validateCategory(input.categoryId());
        validateMerchantCategory(ownerId, input.merchantCategoryId());
        Goods updated = new Goods(goods.id(), goods.storeId(), input.name(), input.description(),
                input.price(), input.originalPrice(), input.image(), input.categoryId(),
                input.merchantCategoryId(), input.stock(), goods.version(),
                goods.sales(), goods.rating(), input.tag() == null ? "" : input.tag(),
                input.status() < 0 ? goods.status() : input.status(), goods.createTime());
        goodsDao.update(updated);
        return goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品更新失败"));
    }

    /** 快速补货/清库存（演进项，见大纲 8.4）。 */
    public Goods updateStock(long ownerId, long goodsId, int stock) {
        if (stock < 0) {
            throw new BizException("库存不能为负数");
        }
        Goods goods = goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品不存在"));
        requireOwned(ownerId, goods.storeId());
        goodsDao.updateStock(goodsId, stock);
        return goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品更新失败"));
    }

    // ============ 商户分类（演进项，见大纲 8.3） ============

    public List<Category> merchantCategories(long ownerId) {
        return storeDao.listMerchantCategories(ownerId);
    }

    /** 用户端：店铺详情展示的店内商户分类。 */
    public List<Category> publicMerchantCategories(long storeId) {
        Store store = storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        return storeDao.listMerchantCategories(store.ownerId());
    }

    public Category createMerchantCategory(long ownerId, String name, int sort) {
        String normalized = normalizeRequired(name, "分类名称不能为空");
        if (storeDao.merchantCategoryNameExists(ownerId, normalized, 0)) {
            throw new BizException("分类名称已存在");
        }
        long id = storeDao.insertMerchantCategory(ownerId, normalized, Math.max(sort, 0));
        return storeDao.findCategoryById(id).orElseThrow(() -> new BizException("分类创建失败"));
    }

    public Category updateMerchantCategory(long ownerId, long categoryId, String name, int sort) {
        requireMerchantCategoryOwned(ownerId, categoryId);
        String normalized = normalizeRequired(name, "分类名称不能为空");
        if (storeDao.merchantCategoryNameExists(ownerId, normalized, categoryId)) {
            throw new BizException("分类名称已存在");
        }
        storeDao.updateMerchantCategory(categoryId, normalized, Math.max(sort, 0));
        return storeDao.findCategoryById(categoryId).orElseThrow(() -> new BizException("分类更新失败"));
    }

    public void deleteMerchantCategory(long ownerId, long categoryId) {
        requireMerchantCategoryOwned(ownerId, categoryId);
        if (storeDao.countGoodsByMerchantCategory(categoryId) > 0) {
            throw new BizException("该分类下仍有商品，请先调整商品分类后再删除");
        }
        storeDao.deleteMerchantCategory(categoryId);
    }

    private void requireMerchantCategoryOwned(long ownerId, long categoryId) {
        if (!storeDao.merchantCategoryOwned(categoryId, ownerId)) {
            throw new BizException(403, "无权操作该分类");
        }
    }

    private void validateMerchantCategory(long ownerId, long merchantCategoryId) {
        if (merchantCategoryId > 0 && !storeDao.merchantCategoryOwned(merchantCategoryId, ownerId)) {
            throw new BizException("商户分类不存在");
        }
    }

    public void deleteGoods(long ownerId, long goodsId) {
        Goods goods = goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品不存在"));
        requireOwned(ownerId, goods.storeId());
        goodsDao.delete(goodsId);
    }

    private Store requireOwned(long ownerId, long storeId) {
        Store store = storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        if (store.ownerId() != ownerId) {
            throw new BizException(403, "无权操作该店铺");
        }
        return store;
    }

    private void validateGoodsInput(GoodsInput input) {
        if (input == null || input.name() == null || input.name().isBlank()) {
            throw new BizException("商品名称不能为空");
        }
        if (!Double.isFinite(input.price()) || input.price() <= 0
                || !Double.isFinite(input.originalPrice()) || input.originalPrice() < 0) {
            throw new BizException("商品价格必须为正数");
        }
        if (input.status() != 0 && input.status() != 1) {
            throw new BizException("商品状态不合法");
        }
        if (input.stock() < 0) {
            throw new BizException("库存不能为负数");
        }
    }

    private void validateCategory(int categoryId) {
        if (categoryId <= 0 || !storeDao.categoryExists(categoryId)) {
            throw new BizException("店铺或商品分类不存在");
        }
    }

    private Store.StoreView toView(Store store) {
        List<String> tags = parseList(store.tags());
        List<Integer> categoryIds = parseIds(store.categoryIds());
        return store.toView(tags, categoryIds);
    }

    private List<String> parseList(String json) {
        if (json == null || json.isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<List<String>>() {
            });
        } catch (Exception e) {
            return List.of();
        }
    }

    private List<Integer> parseIds(String json) {
        if (json == null || json.isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<List<Integer>>() {
            });
        } catch (Exception e) {
            return List.of();
        }
    }

    /**
     * 店铺信息修改项（可选字段）
     */
    public record StorePatch(String name, double deliveryFee, double minOrder, String deliveryTime,
                             String notice, int status) {
    }

    /**
     * 商品创建/编辑项（merchantCategoryId=商户分类，0=未分组；stock=库存）
     */
    public record GoodsInput(String name, String description, double price, double originalPrice,
                             String image, int categoryId, String tag, int status,
                             long merchantCategoryId, int stock) {
    }

    private String normalizeRequired(String value, String message) {
        if (value == null || value.isBlank()) {
            throw new BizException(message);
        }
        return value.trim();
    }
}
