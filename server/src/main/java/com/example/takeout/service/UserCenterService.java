package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.CouponDao;
import com.example.takeout.dao.FavoriteDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.ReviewDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.model.Address;
import com.example.takeout.model.Coupon;
import com.example.takeout.model.Goods;
import com.example.takeout.model.Review;
import com.example.takeout.model.Store;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;

/**
 * 用户中心服务：优惠券、收藏、地址、评价浏览、搜索
 */
@Service
public class UserCenterService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final CouponDao couponDao;
    private final FavoriteDao favoriteDao;
    private final AddressDao addressDao;
    private final ReviewDao reviewDao;
    private final StoreDao storeDao;
    private final GoodsDao goodsDao;
    private final ObjectMapper objectMapper;

    public UserCenterService(CouponDao couponDao, FavoriteDao favoriteDao, AddressDao addressDao,
                             ReviewDao reviewDao, StoreDao storeDao, GoodsDao goodsDao, ObjectMapper objectMapper) {
        this.couponDao = couponDao;
        this.favoriteDao = favoriteDao;
        this.addressDao = addressDao;
        this.reviewDao = reviewDao;
        this.storeDao = storeDao;
        this.goodsDao = goodsDao;
        this.objectMapper = objectMapper;
    }

    // ============ 优惠券 ============

    public List<Coupon> listCoupons(long userId) {
        return couponDao.listByUser(userId);
    }

    public Coupon claimCoupon(long userId, long storeId, String name, double threshold, double amount) {
        if (name == null || name.isBlank()) {
            throw new BizException("优惠券名称不能为空");
        }
        if (amount <= 0) {
            throw new BizException("优惠金额必须大于 0");
        }
        String expire = LocalDateTime.now().plusDays(30).format(FMT);
        long id = couponDao.insert(userId, storeId, name, threshold, amount, expire, "claim",
                LocalDateTime.now().format(FMT));
        return couponDao.listByUser(userId).stream()
                .filter(c -> c.id() == id)
                .findFirst()
                .orElseThrow(() -> new BizException("领券失败"));
    }

    // ============ 收藏 ============

    public List<Store.StoreView> listFavorites(long userId) {
        return favoriteDao.listByUser(userId).stream()
                .map(f -> storeDao.findById(f.storeId()))
                .filter(java.util.Optional::isPresent)
                .map(java.util.Optional::get)
                .map(this::toView)
                .toList();
    }

    public boolean isFavorited(long userId, long storeId) {
        return favoriteDao.exists(userId, storeId);
    }

    public boolean toggleFavorite(long userId, long storeId) {
        storeDao.findById(storeId).orElseThrow(() -> new BizException("店铺不存在"));
        if (favoriteDao.exists(userId, storeId)) {
            favoriteDao.delete(userId, storeId);
            return false;
        }
        favoriteDao.insert(userId, storeId, LocalDateTime.now().format(FMT));
        return true;
    }

    // ============ 地址 ============

    public List<Address> listAddresses(long userId) {
        return addressDao.listByUser(userId);
    }

    public Address addAddress(long userId, String name, String phone, String detail, int isDefault) {
        if (name == null || name.isBlank() || phone == null || phone.isBlank() || detail == null || detail.isBlank()) {
            throw new BizException("姓名/电话/地址不能为空");
        }
        long id = addressDao.insert(userId, name, phone, detail, isDefault, LocalDateTime.now().format(FMT));
        return addressDao.listByUser(userId).stream()
                .filter(a -> a.id() == id)
                .findFirst()
                .orElseThrow(() -> new BizException("地址添加失败"));
    }

    public void deleteAddress(long userId, long id) {
        addressDao.delete(userId, id);
    }

    public void setDefaultAddress(long userId, long id) {
        addressDao.setDefault(userId, id);
    }

    // ============ 评价浏览 ============

    public List<Review.ReviewView> storeReviews(long storeId) {
        return reviewDao.listByStore(storeId).stream().map(this::toReviewView).toList();
    }

    // ============ 搜索 ============

    public List<Store.StoreView> search(String keyword) {
        if (keyword == null || keyword.isBlank()) {
            return List.of();
        }
        String kw = keyword.trim().toLowerCase(Locale.ROOT);
        return storeDao.listAll().stream()
                .filter(s -> s.name().toLowerCase(Locale.ROOT).contains(kw)
                        || matchGoods(s.id(), kw)
                        || matchNotice(s.notice(), kw))
                .map(this::toView)
                .toList();
    }

    private boolean matchGoods(long storeId, String kw) {
        return goodsDao.listByStore(storeId).stream()
                .anyMatch(g -> g.name().toLowerCase(Locale.ROOT).contains(kw));
    }

    private boolean matchNotice(String notice, String kw) {
        return notice != null && notice.toLowerCase(Locale.ROOT).contains(kw);
    }

    // ============ 工具 ============

    private Store.StoreView toView(Store store) {
        List<String> tags = parseList(store.tags());
        List<Integer> categoryIds = parseIds(store.categoryIds());
        return store.toView(tags, categoryIds);
    }

    private Review.ReviewView toReviewView(Review review) {
        return review.toView(parseList(review.tags()));
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
}
