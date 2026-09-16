package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.model.Category;
import com.example.takeout.model.Goods;
import com.example.takeout.model.GoodsSpec;
import com.example.takeout.model.Seckill;
import com.example.takeout.model.Store;
import com.example.takeout.model.SpecialGoods;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 店铺与商品服务：浏览、商户管理（含多规格 SKU 维护）
 */
@Service
public class StoreService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final StoreDao storeDao;
    private final GoodsDao goodsDao;
    private final GoodsSpecDao specDao;
    private final SeckillDao seckillDao;
    private final ObjectMapper objectMapper;
    private final HotDataCacheService cache;

    public StoreService(StoreDao storeDao, GoodsDao goodsDao, GoodsSpecDao specDao, SeckillDao seckillDao,
                        ObjectMapper objectMapper, HotDataCacheService cache) {
        this.storeDao = storeDao;
        this.goodsDao = goodsDao;
        this.specDao = specDao;
        this.seckillDao = seckillDao;
        this.objectMapper = objectMapper;
        this.cache = cache;
    }

    public List<Category> listCategories() {
        // 热点：首页分类导航，全量用户高频读取，TTL+抖动防雪崩
        return cache.get(HotDataCacheService.Keys.CATEGORIES,
                new TypeReference<List<Category>>() {
                },
                storeDao::listCategories);
    }

    public List<Store.StoreView> listStores(Integer categoryId) {
        return listStores(categoryId, null, null);
    }

    public List<Store.StoreView> listStores(Integer categoryId, Double latitude, Double longitude) {
        if (categoryId != null && categoryId < 0) {
            throw new BizException("分类参数不合法");
        }
        if (categoryId != null && categoryId > 0 && !storeDao.categoryExists(categoryId)) {
            throw new BizException(404, "分类不存在");
        }
        return cache.get(HotDataCacheService.Keys.storeList(categoryId, latitude, longitude),
                new TypeReference<List<Store.StoreView>>() {
                },
                () -> {
                    List<Store> stores = categoryId == null || categoryId == 0
                            ? storeDao.listAll()
                            : storeDao.listByCategory(categoryId);
                    return stores.stream().map(store -> toView(store, latitude, longitude)).toList();
                });
    }

    public List<Store.StoreView> recommendedStores(double maxDistanceKm, int limit) {
        return recommendedStores(maxDistanceKm, limit, null, null);
    }

    public List<Store.StoreView> recommendedStores(double maxDistanceKm, int limit,
                                                   Double latitude, Double longitude) {
        if (!Double.isFinite(maxDistanceKm) || maxDistanceKm <= 0 || maxDistanceKm > 20) {
            throw new BizException("查询距离范围必须在 0 到 20 公里之间");
        }
        if (limit <= 0 || limit > 50) {
            throw new BizException("推荐店铺数量必须在 1 到 50 之间");
        }
        return cache.get(HotDataCacheService.Keys.recommendedStores(maxDistanceKm, limit, latitude, longitude),
                new TypeReference<List<Store.StoreView>>() {
                },
                () -> storeDao.listRecommended().stream()
                        .map(store -> store.withDistance(latitude, longitude))
                        .filter(store -> parseDistance(store.distance()) <= maxDistanceKm)
                        .sorted(Comparator.comparingDouble((Store store) -> parseDistance(store.distance()))
                                .thenComparing(Comparator.comparingDouble(Store::rating).reversed()))
                        .limit(limit)
                        .map(this::toView)
                        .toList());
    }

    public Store.StoreView storeDetail(long id) {
        // 热点：店铺详情页高频访问；店铺不存在时由缓存写入空值占位防穿透
        return cache.get(HotDataCacheService.Keys.storeDetail(id),
                new TypeReference<Store.StoreView>() {
                },
                () -> storeDao.findById(id).map(this::toView).orElse(null));
    }

    public List<Goods> listGoods(long storeId) {
        storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        return cache.get(HotDataCacheService.Keys.storeGoods(storeId),
                new TypeReference<List<Goods>>() {
                },
                () -> goodsDao.listByStore(storeId));
    }

    /**
     * 店铺/商品数据变更后的缓存失效。
     * 店铺名、距离、起送价、菜品价格库存等会同时影响店铺列表、榜单、秒杀与特价等
     * 多个聚合视图，因此按模式整体失效，避免遗漏造成长期脏读。
     */
    private void invalidateStoreAndGoodsCache() {
        for (String pattern : HotDataCacheService.Keys.STORE_GOODS_PATTERNS) {
            cache.evictByPattern(pattern);
        }
    }

    public List<SpecialGoods> listSpecialGoods(int limit) {
        return listSpecialGoods(limit, null, null);
    }

    public List<SpecialGoods> listSpecialGoods(int limit, Double latitude, Double longitude) {
        if (limit <= 0 || limit > 50) {
            throw new BizException("特价团购商品数量必须在 1 到 50 之间");
        }
        return cache.get(HotDataCacheService.Keys.specialGoods(limit, latitude, longitude),
                new TypeReference<List<SpecialGoods>>() {
                },
                () -> withDistance(goodsDao.listSpecialGoods(limit), latitude, longitude));
    }

    // ============ 营销：榜单 / 限时秒杀 / 凑单 ============

    /** 店铺榜：按累计月销量与评分排序（仅营业店铺）。 */
    public List<Store.StoreView> rankStores(int limit, Double latitude, Double longitude) {
        requireRankLimit(limit);
        return cache.get(HotDataCacheService.Keys.rankStores(limit, latitude, longitude),
                new TypeReference<List<Store.StoreView>>() {
                },
                () -> storeDao.listAll().stream()
                        .filter(store -> store.status() == 1)
                        .sorted(Comparator.comparingInt(Store::monthlySales).reversed()
                                .thenComparing(Comparator.comparingDouble(Store::rating).reversed()))
                        .limit(limit)
                        .map(store -> toView(store, latitude, longitude))
                        .toList());
    }

    /** 菜品榜（热销榜）：跨店铺按累计销量排序。 */
    public List<SpecialGoods> rankGoods(int limit, Double latitude, Double longitude) {
        requireRankLimit(limit);
        return cache.get(HotDataCacheService.Keys.rankGoods(limit, latitude, longitude),
                new TypeReference<List<SpecialGoods>>() {
                },
                () -> withDistance(goodsDao.listTopGoods(limit), latitude, longitude));
    }

    /**
     * 首页秒杀专区：进行中且仍有名额的秒杀。
     * 秒杀名额（sold）会随下单变化，因此 TTL 取较短值由下单/取消时显式失效兜底。
     */
    public List<Seckill.SeckillView> listSeckills(int limit, Double latitude, Double longitude) {
        if (limit <= 0 || limit > 50) {
            throw new BizException("秒杀商品数量必须在 1 到 50 之间");
        }
        return cache.get(HotDataCacheService.Keys.seckills(limit, latitude, longitude),
                new TypeReference<List<Seckill.SeckillView>>() {
                },
                () -> {
                    String now = LocalDateTime.now().format(FMT);
                    return seckillDao.listActiveViews(limit, now).stream()
                            .map(view -> new Seckill.SeckillView(view.id(), view.goodsId(), view.goodsName(),
                                    view.image(), view.originalPrice(), view.price(), view.quota(), view.sold(),
                                    view.startTime(), view.endTime(), view.storeId(), view.storeName(),
                                    normalizeDistance(view.storeId(), view.storeDistance(), latitude, longitude),
                                    view.remainSeconds()))
                            .toList();
                });
    }

    /**
     * 凑单提示：返回还差多少元起送，以及店内最便宜的几款菜品。
     * amount 为用户当前已选商品金额；已足起送价时 gap=0 且不返回推荐。
     */
    public BundleView bundle(long storeId, double amount) {
        if (!Double.isFinite(amount) || amount < 0) {
            throw new BizException("金额参数不合法");
        }
        Store store = storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        double gap = round2(Math.max(store.minOrder() - amount, 0));
        List<Goods> suggestions = gap <= 0 ? List.of() : goodsDao.listCheapest(storeId, 4);
        return new BundleView(store.id(), store.name(), store.minOrder(), round2(amount), gap, suggestions);
    }

    private void requireRankLimit(int limit) {
        if (limit <= 0 || limit > 50) {
            throw new BizException("榜单数量必须在 1 到 50 之间");
        }
    }

    private List<SpecialGoods> withDistance(List<SpecialGoods> items, Double latitude, Double longitude) {
        return items.stream().map(item -> {
            Store store = storeDao.findById(item.goods().storeId()).orElse(null);
            String distance = store != null
                    ? store.withDistance(latitude, longitude).distance()
                    : Store.normalizeDistance(item.storeDistance());
            return new SpecialGoods(item.goods(), item.storeName(), distance);
        }).toList();
    }

    private String normalizeDistance(long storeId, String fallback, Double latitude, Double longitude) {
        if (latitude == null || longitude == null) {
            return Store.normalizeDistance(fallback);
        }
        return storeDao.findById(storeId).map(store -> store.withDistance(latitude, longitude).distance())
                .orElseGet(() -> Store.normalizeDistance(fallback));
    }

    private double round2(double value) {
        return Math.round(value * 100.0) / 100.0;
    }

    /** 凑单视图：gap>0 时给出可凑单的店内菜品。 */
    public record BundleView(long storeId, String storeName, double minOrder, double amount,
                             double gap, List<Goods> suggestions) {
    }

    public List<Store.StoreView> merchantStores(long ownerId) {
        return storeDao.listByOwner(ownerId).stream().map(this::toView).toList();
    }

    public List<Goods> merchantGoods(long ownerId, long storeId) {
        requireOwned(ownerId, storeId);
        return goodsDao.listByStoreAll(storeId);
    }

    public Store.StoreView createStore(long ownerId, String name, int categoryId, double deliveryFee,
                                       double minOrder, String deliveryTime, String notice,
                                       String address, Double latitude, Double longitude, int deliveryRadius) {
        String safeName = requireMaxLength(normalizeRequired(name, "店铺名称不能为空"), 128, "店铺名称");
        validateCategory(categoryId);
        if (!Double.isFinite(deliveryFee) || deliveryFee < 0 || !Double.isFinite(minOrder) || minOrder < 0) {
            throw new BizException("配送费和起送价必须为非负数字");
        }
        if (deliveryRadius < 0) {
            throw new BizException("配送半径必须为非负整数（0 表示不限）");
        }
        String normalizedAddress = requireMaxLength(normalizeRequired(address, "店铺地址不能为空"), 512, "店铺地址");
        if (!validCoordinates(latitude, longitude)) {
            throw new BizException("店铺地址定位失败，请重新选择地址");
        }
        String now = LocalDateTime.now().format(FMT);
        Store store = new Store(0, safeName, "", 4.5, 0, deliveryFee, minOrder,
                deliveryTime == null || deliveryTime.isBlank() ? "30分钟"
                        : requireMaxLength(deliveryTime, 32, "配送时间"),
                "0.0km", "[\"新店特惠\"]", requireMaxLength(notice, 512, "店铺公告"),
                normalizedAddress, latitude, longitude, categoryId, "[" + categoryId + "]", ownerId, 1, 0, now, deliveryRadius);
        long id = storeDao.insert(store);
        invalidateStoreAndGoodsCache();
        return storeDetail(id);
    }

    public Store.StoreView updateStore(long ownerId, long storeId, StorePatch patch) {
        Store store = requireOwned(ownerId, storeId);
        // 与创建店铺同口径的有限性校验：NaN 会让所有比较恒为 false，使起送价校验被完全绕过；
        // 1e400 这类字面量会被解析成 Infinity，使该店永远达不到起送价。负数仍按「不修改」处理。
        if (!Double.isFinite(patch.deliveryFee()) || !Double.isFinite(patch.minOrder())) {
            throw new BizException("配送费和起送价必须为有效数字");
        }
        String nextAddress = patch.address() == null ? store.address()
                : requireMaxLength(normalizeRequired(patch.address(), "店铺地址不能为空"), 512, "店铺地址");
        String nextName = requireMaxLength(patch.name() == null ? store.name() : patch.name(), 128, "店铺名称");
        String nextNotice = requireMaxLength(patch.notice() == null ? store.notice() : patch.notice(),
                512, "店铺公告");
        String nextDeliveryTime = requireMaxLength(
                patch.deliveryTime() == null ? store.deliveryTime() : patch.deliveryTime(), 32, "配送时间");
        Double nextLatitude = patch.address() == null ? store.latitude() : patch.latitude();
        Double nextLongitude = patch.address() == null ? store.longitude() : patch.longitude();
        int nextRadius = patch.deliveryRadius() < 0 ? store.deliveryRadius() : patch.deliveryRadius();
        if (!nextAddress.isBlank() && !validCoordinates(nextLatitude, nextLongitude)) {
            throw new BizException("店铺地址定位失败，请重新选择地址");
        }
        Store updated = new Store(store.id(), nextName,
                store.image(), store.rating(), store.monthlySales(),
                patch.deliveryFee() < 0 ? store.deliveryFee() : patch.deliveryFee(),
                patch.minOrder() < 0 ? store.minOrder() : patch.minOrder(),
                nextDeliveryTime,
                store.distance(), store.tags(), nextNotice,
                nextAddress, nextLatitude, nextLongitude,
                store.categoryId(), store.categoryIds(), store.ownerId(),
                patch.status() < 0 ? store.status() : patch.status(), store.recommended(), store.createTime(), nextRadius);
        storeDao.update(updated);
        invalidateStoreAndGoodsCache();
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
                input.tag() == null ? "" : input.tag(), input.special(), 1, now);
        long id = goodsDao.insert(goods);
        applySpecs(id, input.specs());
        invalidateStoreAndGoodsCache();
        return goodsDao.findById(id).orElseThrow(() -> new BizException("商品创建失败"));
    }

    public Goods updateGoods(long ownerId, long goodsId, GoodsInput input) {
        Goods goods = goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品不存在"));
        requireOwned(ownerId, goods.storeId());
        // 有规格时价格/库存由规格聚合，允许传入的 price/stock 缺省
        validateGoodsInput(input, input.specs() != null && !input.specs().isEmpty());
        validateCategory(input.categoryId());
        validateMerchantCategory(ownerId, input.merchantCategoryId());
        if (input.specs() != null) {
            applySpecs(goodsId, input.specs());
        }
        List<GoodsSpec> specs = specDao.listByGoods(goodsId);
        Goods updated = new Goods(goods.id(), goods.storeId(), input.name(), input.description(),
                specs.isEmpty() ? input.price() : minSpecPrice(specs),
                input.originalPrice(), input.image(), input.categoryId(),
                input.merchantCategoryId(), specs.isEmpty() ? input.stock() : sumSpecStock(specs),
                goods.version(), goods.sales(), goods.rating(), input.tag() == null ? "" : input.tag(),
                input.special(), input.status() < 0 ? goods.status() : input.status(), goods.createTime());
        goodsDao.update(updated);
        invalidateStoreAndGoodsCache();
        return goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品更新失败"));
    }

    // ============ 多规格 SKU ============

    /** 商户侧查看菜品规格。 */
    public List<GoodsSpec> listSpecs(long ownerId, long goodsId) {
        Goods goods = goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品不存在"));
        requireOwned(ownerId, goods.storeId());
        return specDao.listByGoods(goodsId);
    }

    /** 整体覆盖菜品规格（保留已有规格 id，新增的插入，未提交的删除）。 */
    public Goods updateSpecs(long ownerId, long goodsId, List<SpecInput> specs) {
        Goods goods = goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品不存在"));
        requireOwned(ownerId, goods.storeId());
        applySpecs(goodsId, specs == null ? List.of() : specs);
        invalidateStoreAndGoodsCache();
        return goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品更新失败"));
    }

    private void applySpecs(long goodsId, List<SpecInput> inputs) {
        List<SpecInput> list = inputs == null ? List.of() : inputs;
        Set<String> names = new HashSet<>();
        for (SpecInput input : list) {
            if (input == null || input.name() == null || input.name().isBlank()) {
                throw new BizException("规格名称不能为空");
            }
            if (!Double.isFinite(input.price()) || input.price() <= 0) {
                throw new BizException("规格「" + input.name() + "」价格必须为正数");
            }
            if (input.stock() < 0) {
                throw new BizException("规格「" + input.name() + "」库存不能为负数");
            }
            if (!names.add(input.name().trim())) {
                throw new BizException("规格名称重复：" + input.name());
            }
        }
        List<GoodsSpec> existing = specDao.listByGoods(goodsId);
        Set<Long> kept = new HashSet<>();
        for (int i = 0; i < list.size(); i++) {
            SpecInput input = list.get(i);
            String name = input.name().trim();
            boolean isExisting = input.id() > 0 && existing.stream().anyMatch(spec -> spec.id() == input.id());
            if (isExisting) {
                specDao.update(input.id(), name, input.price(), input.stock(), i);
                kept.add(input.id());
            } else {
                kept.add(specDao.insert(goodsId, name, input.price(), input.stock(), i));
            }
        }
        specDao.deleteByIds(existing.stream().map(GoodsSpec::id).filter(id -> !kept.contains(id)).toList());
        syncGoodsFromSpecs(goodsId);
    }

    /** 把规格的最低价/库存合计回写到菜品，保证列表与起送价口径一致。 */
    private void syncGoodsFromSpecs(long goodsId) {
        List<GoodsSpec> specs = specDao.listByGoods(goodsId);
        if (specs.isEmpty()) {
            return;
        }
        goodsDao.syncFromSpecs(goodsId, minSpecPrice(specs), sumSpecStock(specs));
    }

    private double minSpecPrice(List<GoodsSpec> specs) {
        return specs.stream().mapToDouble(GoodsSpec::price).min().orElse(0);
    }

    private int sumSpecStock(List<GoodsSpec> specs) {
        return specs.stream().mapToInt(GoodsSpec::stock).sum();
    }

    /** 快速补货/清库存（演进项，见大纲 8.4）。多规格菜品库存由规格聚合，须在规格里调整。 */
    public Goods updateStock(long ownerId, long goodsId, int stock) {
        if (stock < 0) {
            throw new BizException("库存不能为负数");
        }
        Goods goods = goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品不存在"));
        requireOwned(ownerId, goods.storeId());
        if (goods.multiSpec()) {
            throw new BizException("多规格菜品请分别调整各规格库存");
        }
        goodsDao.updateStock(goodsId, stock);
        invalidateStoreAndGoodsCache();
        return goodsDao.findById(goodsId).orElseThrow(() -> new BizException("商品更新失败"));
    }

    // ============ 商户分类（演进项，见大纲 8.3） ============

    public List<Category> merchantCategories(long ownerId) {
        return storeDao.listMerchantCategories(ownerId);
    }

    /** 用户端：店铺详情展示的店内商户分类。 */
    public List<Category> publicMerchantCategories(long storeId) {
        Store store = storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        return cache.get(HotDataCacheService.Keys.storeCategories(storeId),
                new TypeReference<List<Category>>() {
                },
                () -> storeDao.listMerchantCategories(store.ownerId()));
    }

    public Category createMerchantCategory(long ownerId, String name, int sort) {
        String normalized = requireMaxLength(normalizeRequired(name, "分类名称不能为空"), 32, "分类名称");
        if (storeDao.merchantCategoryNameExists(ownerId, normalized, 0)) {
            throw new BizException("分类名称已存在");
        }
        long id = storeDao.insertMerchantCategory(ownerId, normalized, Math.max(sort, 0));
        invalidateStoreAndGoodsCache();
        return storeDao.findCategoryById(id).orElseThrow(() -> new BizException("分类创建失败"));
    }

    public Category updateMerchantCategory(long ownerId, long categoryId, String name, int sort) {
        requireMerchantCategoryOwned(ownerId, categoryId);
        String normalized = requireMaxLength(normalizeRequired(name, "分类名称不能为空"), 32, "分类名称");
        if (storeDao.merchantCategoryNameExists(ownerId, normalized, categoryId)) {
            throw new BizException("分类名称已存在");
        }
        storeDao.updateMerchantCategory(categoryId, normalized, Math.max(sort, 0));
        invalidateStoreAndGoodsCache();
        return storeDao.findCategoryById(categoryId).orElseThrow(() -> new BizException("分类更新失败"));
    }

    public void deleteMerchantCategory(long ownerId, long categoryId) {
        requireMerchantCategoryOwned(ownerId, categoryId);
        if (storeDao.countGoodsByMerchantCategory(categoryId) > 0) {
            throw new BizException("该分类下仍有商品，请先调整商品分类后再删除");
        }
        storeDao.deleteMerchantCategory(categoryId);
        invalidateStoreAndGoodsCache();
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
        invalidateStoreAndGoodsCache();
    }

    private Store requireOwned(long ownerId, long storeId) {
        Store store = storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        if (store.ownerId() != ownerId) {
            throw new BizException(403, "无权操作该店铺");
        }
        return store;
    }

    private void validateGoodsInput(GoodsInput input) {
        validateGoodsInput(input, false);
    }

    private void validateGoodsInput(GoodsInput input, boolean multiSpec) {
        if (input == null || input.name() == null || input.name().isBlank()) {
            throw new BizException("商品名称不能为空");
        }
        // 列宽：goods.name 128 / description 512 / tag 32 / image 255 / goods_specs.name 64，
        // 超长会因列宽溢出变成 500
        requireMaxLength(input.name(), 128, "商品名称");
        requireMaxLength(input.description(), 512, "商品描述");
        requireMaxLength(input.image(), 255, "商品图片地址");
        requireMaxLength(input.tag(), 32, "商品标签");
        if (input.specs() != null) {
            for (SpecInput spec : input.specs()) {
                if (spec != null) {
                    requireMaxLength(spec.name(), 64, "规格名称");
                }
            }
        }
        double price = input.price();
        if (multiSpec) {
            // 多规格菜品的价格/库存由规格聚合，允许提交 0（后续由规格回写覆盖）
            if (!Double.isFinite(price) || price < 0) {
                throw new BizException("商品价格必须为正数");
            }
        } else if (!Double.isFinite(price) || price <= 0) {
            throw new BizException("商品价格必须为正数");
        }
        if (!Double.isFinite(input.originalPrice()) || input.originalPrice() < 0) {
            throw new BizException("商品价格必须为正数");
        }
        if (input.status() != 0 && input.status() != 1) {
            throw new BizException("商品状态不合法");
        }
        if (!multiSpec && input.stock() < 0) {
            throw new BizException("库存不能为负数");
        }
        if (input.special() && input.originalPrice() <= price) {
            throw new BizException("特价商品原价必须高于特价价");
        }
    }

    private void validateCategory(int categoryId) {
        if (categoryId <= 0 || !storeDao.categoryExists(categoryId)) {
            throw new BizException("店铺或商品分类不存在");
        }
    }

    private Store.StoreView toView(Store store) {
        return toView(store, null, null);
    }

    private Store.StoreView toView(Store store, Double latitude, Double longitude) {
        Store displayStore = store.withDistance(latitude, longitude);
        List<String> tags = parseList(store.tags());
        List<Integer> categoryIds = parseIds(store.categoryIds());
        return displayStore.toView(tags, categoryIds, latitude, longitude);
    }

    private double parseDistance(String distance) {
        if (distance == null || distance.isBlank()) {
            return Double.MAX_VALUE;
        }
        try {
            return Double.parseDouble(distance.toLowerCase().replace("km", "").trim());
        } catch (NumberFormatException ignored) {
            return Double.MAX_VALUE;
        }
    }

    private boolean validCoordinates(Double latitude, Double longitude) {
        return latitude != null && longitude != null
                && Double.isFinite(latitude) && Double.isFinite(longitude)
                && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
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
                             String notice, String address, Double latitude, Double longitude, int status,
                             int deliveryRadius) {
    }

    /**
     * 商品创建/编辑项（merchantCategoryId=商户分类，0=未分组；stock=库存；
     * specs=多规格列表，null 表示本次不修改规格，空数组表示清空规格）
     */
    public record GoodsInput(String name, String description, double price, double originalPrice,
                             String image, int categoryId, String tag, int status,
                             long merchantCategoryId, int stock, boolean special,
                             List<SpecInput> specs) {
    }

    /** 规格提交项（id=0 表示新增）。 */
    public record SpecInput(long id, String name, double price, int stock) {
    }

    private String normalizeRequired(String value, String message) {
        if (value == null || value.isBlank()) {
            throw new BizException(message);
        }
        return value.trim();
    }

    /** 列宽上限校验：超长会在写库时抛 500，这里提前给出可读的 400 提示。 */
    private static String requireMaxLength(String value, int maxLength, String field) {
        String safe = value == null ? "" : value.trim();
        if (safe.length() > maxLength) {
            throw new BizException(field + "最多 " + maxLength + " 个字符");
        }
        return safe;
    }
}
