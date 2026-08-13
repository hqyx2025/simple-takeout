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
        String now = LocalDateTime.now().format(FMT);
        Goods goods = new Goods(0, storeId, input.name(), input.description(),
                input.price(), input.originalPrice(), input.image(), input.categoryId(),
                0, 4.5, input.tag() == null ? "" : input.tag(), 1, now);
        long id = goodsDao.insert(goods);
        return goodsDao.findById(id).orElseThrow(() -> new BizException("商品创建失败"));
    }

    public Goods updateGoods(long ownerId, long goodsId, GoodsInput input) {
        Goods goods = goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品不存在"));
        requireOwned(ownerId, goods.storeId());
        Goods updated = new Goods(goods.id(), goods.storeId(), input.name(), input.description(),
                input.price(), input.originalPrice(), input.image(), input.categoryId(),
                goods.sales(), goods.rating(), input.tag() == null ? "" : input.tag(),
                input.status() < 0 ? goods.status() : input.status(), goods.createTime());
        goodsDao.update(updated);
        return goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品更新失败"));
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
     * 商品创建/编辑项
     */
    public record GoodsInput(String name, String description, double price, double originalPrice,
                             String image, int categoryId, String tag, int status) {
    }
}
