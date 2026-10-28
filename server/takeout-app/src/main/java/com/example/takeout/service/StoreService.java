package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.EmployeeDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.model.Category;
import com.example.takeout.model.Employee;
import com.example.takeout.model.Goods;
import com.example.takeout.model.GoodsSpec;
import com.example.takeout.model.MarketingActivity;
import com.example.takeout.model.Seckill;
import com.example.takeout.model.Setmeal;
import com.example.takeout.model.SetmealItem;
import com.example.takeout.model.SpecialGoods;
import com.example.takeout.model.Store;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.time.format.DateTimeParseException;
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
    private final EmployeeDao employeeDao;

    public StoreService(StoreDao storeDao, GoodsDao goodsDao, GoodsSpecDao specDao, SeckillDao seckillDao,
                        ObjectMapper objectMapper, HotDataCacheService cache, EmployeeDao employeeDao) {
        this.storeDao = storeDao;
        this.goodsDao = goodsDao;
        this.specDao = specDao;
        this.seckillDao = seckillDao;
        this.objectMapper = objectMapper;
        this.cache = cache;
        this.employeeDao = employeeDao;
    }

    public List<Category> listCategories() {
        // 热点：首页分类导航，全量用户高频读取，TTL+抖动防雪崩
        return cache.get(HotDataCacheService.Keys.CATEGORIES,
                new TypeReference<List<Category>>() {
                },
                storeDao::listCategories);
    }

    /** 店铺当前生效的营销活动（折扣/新客立减/满赠），供前端展示。 */
    public List<MarketingActivity> listStoreActivities(long storeId) {
        return storeDao.listActiveMarketingActivities(storeId, LocalDateTime.now().format(FMT));
    }

    /** 商户活动管理：只允许店主/该店启用员工操作。 */
    public List<MarketingActivity> merchantActivities(long ownerId, long storeId) {
        requireOwned(ownerId, storeId);
        return storeDao.listMarketingActivities(storeId);
    }

    @Transactional
    public MarketingActivity createMarketingActivity(long ownerId, long storeId, MarketingActivityInput input) {
        requireOwned(ownerId, storeId);
        MarketingActivity normalized = normalizeMarketingActivity(0, storeId, input, LocalDateTime.now().format(FMT));
        long id = storeDao.insertMarketingActivity(normalized);
        invalidateStoreAndGoodsCache();
        return storeDao.findMarketingActivity(storeId, id).orElseThrow(() -> new BizException("活动创建失败"));
    }

    @Transactional
    public MarketingActivity updateMarketingActivity(long ownerId, long storeId, long activityId,
                                                      MarketingActivityInput input) {
        requireOwned(ownerId, storeId);
        MarketingActivity current = storeDao.findMarketingActivity(storeId, activityId)
                .orElseThrow(() -> new BizException("活动不存在或不属于该店铺"));
        MarketingActivity normalized = normalizeMarketingActivity(activityId, storeId, input, current.createTime());
        storeDao.updateMarketingActivity(normalized);
        invalidateStoreAndGoodsCache();
        return storeDao.findMarketingActivity(storeId, activityId)
                .orElseThrow(() -> new BizException("活动更新失败"));
    }

    @Transactional
    public void deleteMarketingActivity(long ownerId, long storeId, long activityId) {
        requireOwned(ownerId, storeId);
        storeDao.findMarketingActivity(storeId, activityId)
                .orElseThrow(() -> new BizException("活动不存在或不属于该店铺"));
        storeDao.deleteMarketingActivity(storeId, activityId);
        invalidateStoreAndGoodsCache();
    }

    @Transactional
    public MarketingActivity updateMarketingActivityStatus(long ownerId, long storeId, long activityId, int status) {
        requireOwned(ownerId, storeId);
        MarketingActivity current = storeDao.findMarketingActivity(storeId, activityId)
                .orElseThrow(() -> new BizException("活动不存在或不属于该店铺"));
        if (status != 0 && status != 1) {
            throw new BizException("活动状态不合法");
        }
        storeDao.updateMarketingActivity(new MarketingActivity(current.id(), current.storeId(), current.type(),
                current.title(), current.discountRate(), current.reduceAmount(), current.threshold(),
                current.giftGoodsId(), current.startTime(), current.endTime(), status, current.createTime()));
        invalidateStoreAndGoodsCache();
        return storeDao.findMarketingActivity(storeId, activityId)
                .orElseThrow(() -> new BizException("活动状态更新失败"));
    }

    private MarketingActivity normalizeMarketingActivity(long id, long storeId, MarketingActivityInput input,
                                                          String createTime) {
        if (input == null) {
            throw new BizException("活动参数不能为空");
        }
        String type = requireMaxLength(normalizeRequired(input.type(), "活动类型不能为空"), 16, "活动类型").toUpperCase();
        if (!Set.of("DISCOUNT", "NEW_USER", "GIFT").contains(type)) {
            throw new BizException("活动类型不支持");
        }
        String title = requireMaxLength(normalizeRequired(input.title(), "活动标题不能为空"), 64, "活动标题");
        if (!Double.isFinite(input.discountRate()) || !Double.isFinite(input.reduceAmount())
                || !Double.isFinite(input.threshold()) || input.discountRate() < 0
                || input.reduceAmount() < 0 || input.threshold() < 0) {
            throw new BizException("活动优惠参数不合法");
        }
        if ("DISCOUNT".equals(type) && (input.discountRate() <= 0 || input.discountRate() >= 1)) {
            throw new BizException("折扣率必须在 0 和 1 之间");
        }
        if ("NEW_USER".equals(type) && input.reduceAmount() <= 0) {
            throw new BizException("新客立减金额必须大于 0");
        }
        long giftGoodsId = input.giftGoodsId();
        if ("GIFT".equals(type)) {
            if (input.threshold() <= 0 || giftGoodsId <= 0) {
                throw new BizException("满赠活动需要正数门槛和赠品");
            }
            Goods gift = goodsDao.findById(giftGoodsId).orElseThrow(() -> new BizException("赠品商品不存在"));
            if (gift.storeId() != storeId) {
                throw new BizException(403, "赠品商品不属于该店铺");
            }
            if (gift.multiSpec()) {
                throw new BizException("赠品暂不支持多规格商品");
            }
        } else {
            giftGoodsId = 0;
        }
        String start = normalizeTime(input.startTime(), "开始时间");
        String end = normalizeTime(input.endTime(), "结束时间");
        if (end.compareTo(start) <= 0) {
            throw new BizException("结束时间必须晚于开始时间");
        }
        if (input.status() != 0 && input.status() != 1) {
            throw new BizException("活动状态不合法");
        }
        return new MarketingActivity(id, storeId, type, title,
                "DISCOUNT".equals(type) ? input.discountRate() : 0,
                "NEW_USER".equals(type) ? input.reduceAmount() : 0,
                "GIFT".equals(type) ? input.threshold() : 0,
                giftGoodsId, start, end, input.status(), createTime);
    }

    private String normalizeTime(String value, String field) {
        String normalized = requireMaxLength(normalizeRequired(value, field + "不能为空"), 32, field);
        try {
            return LocalDateTime.parse(normalized, FMT).format(FMT);
        } catch (DateTimeParseException ex) {
            throw new BizException(field + "格式必须为 yyyy-MM-dd HH:mm:ss");
        }
    }

    public record MarketingActivityInput(String type, String title, double discountRate, double reduceAmount,
                                         double threshold, long giftGoodsId, String startTime, String endTime,
                                         int status) {
    }

    // ============ 商户限时秒杀管理 ============

    public List<Seckill> merchantSeckills(long ownerId, long storeId) {
        requireOwned(ownerId, storeId);
        return seckillDao.listByStore(storeId);
    }

    @Transactional
    public Seckill createSeckill(long ownerId, long storeId, SeckillInput input) {
        requireOwned(ownerId, storeId);
        SeckillInput normalized = validateSeckill(storeId, input, 0);
        long id = seckillDao.insert(normalized.goodsId(), storeId, normalized.price(), normalized.quota(),
                normalized.startTime(), normalized.endTime(), normalized.status());
        invalidateStoreAndGoodsCache();
        return seckillDao.findById(id).orElseThrow(() -> new BizException("秒杀创建失败"));
    }

    @Transactional
    public Seckill updateSeckill(long ownerId, long storeId, long seckillId, SeckillInput input) {
        requireOwned(ownerId, storeId);
        Seckill current = seckillDao.findById(seckillId)
                .filter(item -> item.storeId() == storeId)
                .orElseThrow(() -> new BizException("秒杀不存在或不属于该店铺"));
        SeckillInput normalized = validateSeckill(storeId, input, current.sold());
        if (normalized.goodsId() != current.goodsId()) {
            throw new BizException("秒杀商品创建后不可更换");
        }
        seckillDao.update(seckillId, storeId, normalized.price(), normalized.quota(), normalized.startTime(),
                normalized.endTime(), normalized.status());
        invalidateStoreAndGoodsCache();
        return seckillDao.findById(seckillId).orElseThrow(() -> new BizException("秒杀更新失败"));
    }

    @Transactional
    public void deleteSeckill(long ownerId, long storeId, long seckillId) {
        requireOwned(ownerId, storeId);
        Seckill current = seckillDao.findById(seckillId)
                .filter(item -> item.storeId() == storeId)
                .orElseThrow(() -> new BizException("秒杀不存在或不属于该店铺"));
        if (current.sold() > 0) {
            throw new BizException("已有销量的秒杀不可删除，请先下架");
        }
        seckillDao.delete(seckillId, storeId);
        invalidateStoreAndGoodsCache();
    }

    @Transactional
    public Seckill updateSeckillStatus(long ownerId, long storeId, long seckillId, int status) {
        requireOwned(ownerId, storeId);
        Seckill current = seckillDao.findById(seckillId)
                .filter(item -> item.storeId() == storeId)
                .orElseThrow(() -> new BizException("秒杀不存在或不属于该店铺"));
        if (status != 0 && status != 1) {
            throw new BizException("秒杀状态不合法");
        }
        seckillDao.update(seckillId, storeId, current.price(), current.quota(), current.startTime(),
                current.endTime(), status);
        invalidateStoreAndGoodsCache();
        return seckillDao.findById(seckillId).orElseThrow(() -> new BizException("秒杀状态更新失败"));
    }

    private SeckillInput validateSeckill(long storeId, SeckillInput input, int sold) {
        if (input == null || input.goodsId() <= 0) {
            throw new BizException("秒杀商品不能为空");
        }
        Goods goods = goodsDao.findById(input.goodsId()).orElseThrow(() -> new BizException("秒杀商品不存在"));
        if (goods.storeId() != storeId) {
            throw new BizException(403, "秒杀商品不属于该店铺");
        }
        if (goods.multiSpec()) {
            throw new BizException("多规格商品暂不支持秒杀");
        }
        if (!Double.isFinite(input.price()) || input.price() <= 0 || input.price() >= goods.price()) {
            throw new BizException("秒杀价必须大于 0 且低于商品现价");
        }
        if (input.quota() <= 0 || input.quota() < sold) {
            throw new BizException("秒杀名额必须大于已售数量");
        }
        String start = normalizeTime(input.startTime(), "开始时间");
        String end = normalizeTime(input.endTime(), "结束时间");
        if (end.compareTo(start) <= 0) {
            throw new BizException("结束时间必须晚于开始时间");
        }
        if (input.status() != 0 && input.status() != 1) {
            throw new BizException("秒杀状态不合法");
        }
        return new SeckillInput(input.goodsId(), input.price(), input.quota(), start, end, input.status());
    }

    public record SeckillInput(long goodsId, double price, int quota, String startTime, String endTime, int status) {
    }

    // ============ 套餐与组合购 ============

    public List<Setmeal> listStoreSetmeals(long storeId) {
        return storeDao.listSetmealsByStore(storeId, true);
    }

    public List<Setmeal> listMerchantSetmeals(long ownerId, long storeId) {
        requireOwned(ownerId, storeId);
        return storeDao.listSetmealsByStore(storeId, false);
    }

    @Transactional
    public Setmeal createSetmeal(long ownerId, long storeId, SetmealInput input) {
        requireOwned(ownerId, storeId);
        String name = requireMaxLength(normalizeRequired(input.name(), "套餐名称不能为空"), 128, "套餐名称");
        String desc = requireMaxLength(input.description() == null ? "" : input.description(), 512, "套餐描述");
        if (!Double.isFinite(input.price()) || input.price() < 0
                || !Double.isFinite(input.originalPrice()) || input.originalPrice() < 0) {
            throw new BizException("套餐价格必须为非负数字");
        }
        if (input.items() == null || input.items().isEmpty()) {
            throw new BizException("套餐必须包含商品");
        }
        for (SetmealItem item : input.items()) {
            if (item == null || item.quantity() <= 0) {
                throw new BizException("套餐商品数量必须大于 0");
            }
            Goods component = goodsDao.findById(item.goodsId())
                    .orElseThrow(() -> new BizException("套餐商品不存在"));
            if (component.storeId() != storeId) {
                throw new BizException(403, "套餐商品不属于该店铺");
            }
            if (component.status() != 1 || component.multiSpec()) {
                throw new BizException("套餐须使用在售的单规格商品");
            }
        }
        long id = storeDao.insertSetmeal(new Setmeal(0, storeId, name, desc, input.price(), input.originalPrice(),
                input.image() == null ? "" : input.image(), 1, LocalDateTime.now().format(FMT), input.items()));
        return storeDao.listSetmealsByStore(storeId, false).stream()
                .filter(s -> s.id() == id)
                .findFirst()
                .orElseThrow(() -> new BizException("套餐创建失败"));
    }

    @Transactional
    public void deleteMerchantSetmeal(long ownerId, long storeId, long setmealId) {
        requireOwned(ownerId, storeId);
        boolean exists = storeDao.listSetmealsByStore(storeId, false).stream().anyMatch(s -> s.id() == setmealId);
        if (!exists) {
            throw new BizException("套餐不存在或不属于该店铺");
        }
        storeDao.deleteSetmeal(setmealId);
    }

    public record SetmealInput(String name, String description, double price, double originalPrice,
                               String image, List<SetmealItem> items) {
    }

    public List<Store.StoreView> listStores(Integer categoryId) {
        return listStores(categoryId, null, null);
    }

    public List<Store.StoreView> listStores(Integer categoryId, Double latitude, Double longitude) {
        requireBrowseCoordinates(latitude, longitude);
        if (categoryId != null && categoryId < 0) {
            throw new BizException("分类参数不合法");
        }
        if (categoryId != null && categoryId > 0 && !storeDao.categoryExists(categoryId)) {
            throw new BizException(404, "分类不存在");
        }
        return sourceStores(categoryId).stream().map(store -> toView(store, latitude, longitude)).toList();
    }

    private List<Store> sourceStores(Integer categoryId) {
        return cache.get(HotDataCacheService.Keys.storeList(categoryId), new TypeReference<List<Store>>() {},
                () -> categoryId == null || categoryId == 0 ? storeDao.listAll() : storeDao.listByCategory(categoryId));
    }

    public List<Store.StoreView> recommendedStores(double maxDistanceKm, int limit) {
        return recommendedStores(maxDistanceKm, limit, null, null);
    }

    public List<Store.StoreView> recommendedStores(double maxDistanceKm, int limit,
                                                   Double latitude, Double longitude) {
        requireBrowseCoordinates(latitude, longitude);
        if (!Double.isFinite(maxDistanceKm) || maxDistanceKm <= 0 || maxDistanceKm > 20) {
            throw new BizException("查询距离范围必须在 0 到 20 公里之间");
        }
        if (limit <= 0 || limit > 50) {
            throw new BizException("推荐店铺数量必须在 1 到 50 之间");
        }
        List<Store> candidates = cache.get(HotDataCacheService.Keys.RECOMMENDED_STORES,
                new TypeReference<List<Store>>() {}, storeDao::listRecommended);
        return candidates.stream()
                .map(store -> store.withDistance(latitude, longitude))
                .filter(store -> parseDistance(store.distance()) <= maxDistanceKm)
                .filter(store -> store.canDeliver(latitude, longitude))
                .sorted(Comparator.comparingDouble((Store store) -> parseDistance(store.distance()))
                        .thenComparing(Comparator.comparingDouble(Store::rating).reversed()))
                .limit(limit).map(store -> toView(store, latitude, longitude)).toList();
    }

    public Store.StoreView storeDetail(long id) {
        Store store = sourceStore(id);
        return store == null ? null : toView(store);
    }

    private Store sourceStore(long id) {
        return cache.get(HotDataCacheService.Keys.storeSource(id), new TypeReference<Store>() {},
                () -> storeDao.findById(id).orElse(null));
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
        DomainEventPublisher.afterCommit(this::evictStoreAndGoodsCache);
    }

    private void evictStoreAndGoodsCache() {
        for (String pattern : HotDataCacheService.Keys.STORE_GOODS_PATTERNS) {
            cache.evictByPattern(pattern);
        }
    }

    public List<SpecialGoods> listSpecialGoods(int limit) {
        return listSpecialGoods(limit, null, null);
    }

    public List<SpecialGoods> listSpecialGoods(int limit, Double latitude, Double longitude) {
        requireBrowseCoordinates(latitude, longitude);
        if (limit <= 0 || limit > 50) {
            throw new BizException("特价团购商品数量必须在 1 到 50 之间");
        }
        List<SpecialGoods> items = cache.get(HotDataCacheService.Keys.SPECIAL_GOODS,
                new TypeReference<List<SpecialGoods>>() {}, () -> goodsDao.listSpecialGoods(50));
        return withDistance(items.stream().limit(limit).toList(), latitude, longitude);
    }

    // ============ 营销：榜单 / 限时秒杀 / 凑单 ============

    /** 店铺榜：按累计月销量与评分排序（仅营业店铺）。 */
    public List<Store.StoreView> rankStores(int limit, Double latitude, Double longitude) {
        requireBrowseCoordinates(latitude, longitude);
        requireRankLimit(limit);
        return sourceStores(null).stream().filter(store -> store.status() == 1)
                .sorted(Comparator.comparingInt(Store::monthlySales).reversed()
                        .thenComparing(Comparator.comparingDouble(Store::rating).reversed()))
                .limit(limit).map(store -> toView(store, latitude, longitude)).toList();
    }

    /** 菜品榜（热销榜）：跨店铺按累计销量排序。 */
    public List<SpecialGoods> rankGoods(int limit, Double latitude, Double longitude) {
        requireBrowseCoordinates(latitude, longitude);
        requireRankLimit(limit);
        List<SpecialGoods> items = cache.get(HotDataCacheService.Keys.RANK_GOODS,
                new TypeReference<List<SpecialGoods>>() {}, () -> goodsDao.listTopGoods(50));
        return withDistance(items.stream().limit(limit).toList(), latitude, longitude);
    }

    /**
     * 首页秒杀专区：进行中且仍有名额的秒杀。
     * 秒杀名额（sold）会随下单变化，因此 TTL 取较短值由下单/取消时显式失效兜底。
     */
    public List<Seckill.SeckillView> listSeckills(int limit, Double latitude, Double longitude) {
        requireBrowseCoordinates(latitude, longitude);
        if (limit <= 0 || limit > 50) {
            throw new BizException("秒杀商品数量必须在 1 到 50 之间");
        }
        List<Seckill.SeckillView> items = cache.get(HotDataCacheService.Keys.SECKILLS,
                new TypeReference<List<Seckill.SeckillView>>() {},
                () -> seckillDao.listActiveViews(50, LocalDateTime.now().format(FMT)));
        return items.stream().limit(limit)
                .map(view -> new Seckill.SeckillView(view.id(), view.goodsId(), view.goodsName(),
                        view.image(), view.originalPrice(), view.price(), view.quota(), view.sold(),
                        view.startTime(), view.endTime(), view.storeId(), view.storeName(),
                        normalizeDistance(view.storeId(), view.storeDistance(), latitude, longitude),
                        view.remainSeconds())).toList();
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
            Store store = sourceStore(item.goods().storeId());
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
        Store store = sourceStore(storeId);
        return store == null ? Store.normalizeDistance(fallback) : store.withDistance(latitude, longitude).distance();
    }

    private double round2(double value) {
        return Math.round(value * 100.0) / 100.0;
    }

    /** 凑单视图：gap>0 时给出可凑单的店内菜品。 */
    public record BundleView(long storeId, String storeName, double minOrder, double amount,
                             double gap, List<Goods> suggestions) {
    }

    public List<Store.StoreView> merchantStores(long ownerId) {
        return storeDao.listAccessibleByMerchant(ownerId).stream().map(this::toView).toList();
    }

    public List<Goods> merchantGoods(long ownerId, long storeId) {
        requireOwned(ownerId, storeId);
        return goodsDao.listByStoreAll(storeId);
    }

    public Store.StoreView createStore(long ownerId, String name, int categoryId, double deliveryFee,
                                       double minOrder, String deliveryTime, String notice,
                                       String address, Double latitude, Double longitude, int deliveryRadius,
                                       String image) {
        String safeName = requireMaxLength(normalizeRequired(name, "店铺名称不能为空"), 128, "店铺名称");
        // 店铺照片：商户上传后返回的相对地址（/uploads/...），未上传为空串
        String safeImage = requireMaxLength(image == null ? "" : image, 255, "店铺图片地址");
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
        Store store = new Store(0, safeName, safeImage, 4.5, 0, deliveryFee, minOrder,
                deliveryTime == null || deliveryTime.isBlank() ? "30分钟"
                        : requireMaxLength(deliveryTime, 32, "配送时间"),
                "0.0km", "[\"新店特惠\"]", requireMaxLength(notice, 512, "店铺公告"),
                normalizedAddress, latitude, longitude, categoryId, "[" + categoryId + "]", ownerId, 1, 0, now, deliveryRadius);
        long id = storeDao.insert(store);
        invalidateStoreAndGoodsCache();
        return storeDetail(id);
    }

    @Transactional
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
        String nextImage = patch.image() == null ? store.image()
                : requireMaxLength(patch.image(), 255, "店铺图片地址");
        if (!nextAddress.isBlank() && !validCoordinates(nextLatitude, nextLongitude)) {
            throw new BizException("店铺地址定位失败，请重新选择地址");
        }
        Store updated = new Store(store.id(), nextName,
                nextImage, store.rating(), store.monthlySales(),
                patch.deliveryFee() < 0 ? store.deliveryFee() : patch.deliveryFee(),
                patch.minOrder() < 0 ? store.minOrder() : patch.minOrder(),
                nextDeliveryTime,
                store.distance(), store.tags(), nextNotice,
                nextAddress, nextLatitude, nextLongitude,
                store.categoryId(), store.categoryIds(), store.ownerId(),
                patch.status() < 0 ? store.status() : patch.status(), store.recommended(), store.createTime(), nextRadius);
        storeDao.update(updated);
        if (patch.status() >= 0) {
            if (patch.status() != 0 && patch.status() != 1) throw new BizException("营业状态无效");
            storeDao.updateStatus(storeId, patch.status());
        }
        invalidateStoreAndGoodsCache();
        return storeDetail(storeId);
    }

    @Transactional
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

    @Transactional
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
    @Transactional
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

    // ============ 门店员工（多门店按店按角色） ============

    public List<Employee> listStoreEmployees(long ownerId, long storeId) {
        requireOwned(ownerId, storeId);
        return employeeDao.listByStore(storeId);
    }

    public Employee addStoreEmployee(long ownerId, long storeId, long userId, String roleName) {
        Store store = requireOwned(ownerId, storeId);
        if (store.ownerId() == userId) {
            throw new BizException("店铺主无需添加为员工");
        }
        String role = roleName == null || roleName.isBlank() ? "店员" : requireMaxLength(roleName.trim(), 16, "员工角色");
        long id = employeeDao.insert(storeId, userId, role, LocalDateTime.now().format(FMT));
        return employeeDao.listByStore(storeId).stream()
                .filter(e -> e.id() == id)
                .findFirst()
                .orElseThrow(() -> new BizException("员工添加失败"));
    }

    public void removeStoreEmployee(long ownerId, long storeId, long employeeId) {
        requireOwned(ownerId, storeId);
        if (!employeeDao.delete(storeId, employeeId)) {
            throw new BizException(404, "员工不存在或不属于该店铺");
        }
    }

    private Store requireOwned(long ownerId, long storeId) {
        Store store = storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        // 多门店员工：店主或该店启用员工均可操作（店主优先，避免员工查询）
        if (store.ownerId() != ownerId && !employeeDao.isEmployee(ownerId, storeId)) {
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

    private void requireBrowseCoordinates(Double latitude, Double longitude) {
        if (latitude == null && longitude == null) return;
        if (!validCoordinates(latitude, longitude)) throw new BizException("定位坐标必须同时提供，纬度为 -90 到 90，经度为 -180 到 180");
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
                             int deliveryRadius, String image) {
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
