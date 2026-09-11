package com.example.takeout.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.example.takeout.common.BizException;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.CartItemEntity;
import com.example.takeout.model.CartItemView;
import com.example.takeout.model.Goods;
import com.example.takeout.model.GoodsSpec;
import com.example.takeout.model.Store;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * 购物车业务：每个用户只能操作自己的购物车，商品详情由现有 JdbcTemplate DAO 查询。
 * 多规格：购物车行按 (用户, 菜品, 规格) 唯一；多规格菜品必须带 specId 才能加入。
 */
@Service
public class CartService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final CartItemMapper cartItemMapper;
    private final GoodsDao goodsDao;
    private final StoreDao storeDao;
    private final GoodsSpecDao specDao;

    public CartService(CartItemMapper cartItemMapper, GoodsDao goodsDao, StoreDao storeDao, GoodsSpecDao specDao) {
        this.cartItemMapper = cartItemMapper;
        this.goodsDao = goodsDao;
        this.storeDao = storeDao;
        this.specDao = specDao;
    }

    public List<CartItemView> list(long userId) {
        List<CartItemEntity> entities = cartItemMapper.selectList(new LambdaQueryWrapper<CartItemEntity>()
                .eq(CartItemEntity::getUserId, userId)
                .orderByDesc(CartItemEntity::getId));
        List<CartItemView> result = new ArrayList<>();
        for (CartItemEntity entity : entities) {
            Goods goods = goodsDao.findById(entity.getGoodsId()).orElse(null);
            if (goods == null) {
                continue;
            }
            long specId = entity.getSpecId() == null ? 0 : entity.getSpecId();
            GoodsSpec spec = null;
            if (specId > 0) {
                spec = goods.specs().stream().filter(item -> item.id() == specId).findFirst().orElse(null);
                // 规格已被商户删除：该购物车行失效，前端提示后由用户自行清理
                if (spec == null) {
                    continue;
                }
            }
            result.add(toView(entity, goods, spec));
        }
        return result;
    }

    public List<CartItemView> add(long userId, long goodsId, int quantity) {
        return add(userId, goodsId, 0, quantity);
    }

    @Transactional
    public List<CartItemView> add(long userId, long goodsId, long specId, int quantity) {
        requirePositiveQuantity(quantity);
        Goods goods = requireAvailableGoods(goodsId);
        GoodsSpec spec = requireSpec(goods, specId);
        CartItemEntity existing = findEntity(userId, goodsId, specId);
        int nextQuantity = existing == null ? quantity : existing.getQuantity() + quantity;
        validateStock(goods, spec, nextQuantity);
        saveQuantity(userId, goodsId, specId, nextQuantity, existing);
        return list(userId);
    }

    public List<CartItemView> setQuantity(long userId, long goodsId, int quantity) {
        return setQuantity(userId, goodsId, 0, quantity);
    }

    @Transactional
    public List<CartItemView> setQuantity(long userId, long goodsId, long specId, int quantity) {
        if (quantity <= 0) {
            return deleteOne(userId, goodsId, specId);
        }
        Goods goods = requireAvailableGoods(goodsId);
        GoodsSpec spec = requireSpec(goods, specId);
        validateStock(goods, spec, quantity);
        saveQuantity(userId, goodsId, specId, quantity, findEntity(userId, goodsId, specId));
        return list(userId);
    }

    public List<CartItemView> deleteOne(long userId, long goodsId) {
        return deleteOne(userId, goodsId, 0);
    }

    @Transactional
    public List<CartItemView> deleteOne(long userId, long goodsId, long specId) {
        cartItemMapper.delete(new LambdaQueryWrapper<CartItemEntity>()
                .eq(CartItemEntity::getUserId, userId)
                .eq(CartItemEntity::getGoodsId, goodsId)
                .eq(CartItemEntity::getSpecId, specId));
        return list(userId);
    }

    @Transactional
    public List<CartItemView> deleteBatch(long userId, List<Long> goodsIds) {
        if (goodsIds == null || goodsIds.isEmpty()) {
            throw new BizException("请选择要删除的商品");
        }
        cartItemMapper.delete(new LambdaQueryWrapper<CartItemEntity>()
                .eq(CartItemEntity::getUserId, userId)
                .in(CartItemEntity::getGoodsId, goodsIds));
        return list(userId);
    }

    @Transactional
    public List<CartItemView> clear(long userId) {
        cartItemMapper.delete(new LambdaQueryWrapper<CartItemEntity>()
                .eq(CartItemEntity::getUserId, userId));
        return List.of();
    }

    private CartItemEntity findEntity(long userId, long goodsId, long specId) {
        return cartItemMapper.selectOne(new LambdaQueryWrapper<CartItemEntity>()
                .eq(CartItemEntity::getUserId, userId)
                .eq(CartItemEntity::getGoodsId, goodsId)
                .eq(CartItemEntity::getSpecId, specId)
                .last("LIMIT 1"));
    }

    private void saveQuantity(long userId, long goodsId, long specId, int quantity, CartItemEntity existing) {
        String now = LocalDateTime.now().format(FMT);
        if (existing == null) {
            CartItemEntity entity = new CartItemEntity();
            entity.setUserId(userId);
            entity.setGoodsId(goodsId);
            entity.setSpecId(specId);
            entity.setQuantity(quantity);
            entity.setCreateTime(now);
            entity.setUpdateTime(now);
            cartItemMapper.insert(entity);
            return;
        }
        existing.setSpecId(specId);
        existing.setQuantity(quantity);
        existing.setUpdateTime(now);
        cartItemMapper.updateById(existing);
    }

    private Goods requireAvailableGoods(long goodsId) {
        Goods goods = goodsDao.findById(goodsId)
                .orElseThrow(() -> new BizException("商品不存在"));
        if (goods.status() != 1) {
            throw new BizException("商品已下架，无法加入购物车");
        }
        return goods;
    }

    /** 多规格菜品必须选中规格；无规格菜品不接受 specId。 */
    private GoodsSpec requireSpec(Goods goods, long specId) {
        if (goods.multiSpec()) {
            if (specId <= 0) {
                throw new BizException("「" + goods.name() + "」请先选择规格");
            }
            return goods.specs().stream()
                    .filter(item -> item.id() == specId)
                    .findFirst()
                    .orElseThrow(() -> new BizException("所选规格已下架，请重新选择"));
        }
        if (specId > 0) {
            throw new BizException("「" + goods.name() + "」不支持规格选择");
        }
        return null;
    }

    private void validateStock(Goods goods, GoodsSpec spec, int quantity) {
        int available = spec == null ? goods.stock() : spec.stock();
        if (quantity > available) {
            throw new BizException("商品库存不足，当前最多可选 " + available + " 份");
        }
    }

    private void requirePositiveQuantity(int quantity) {
        if (quantity <= 0) {
            throw new BizException("商品数量必须大于 0");
        }
    }

    private CartItemView toView(CartItemEntity entity, Goods goods, GoodsSpec spec) {
        String storeName = storeDao.findById(goods.storeId()).map(Store::name).orElse("店铺");
        long specId = spec == null ? 0 : spec.id();
        String specName = spec == null ? "" : spec.name();
        double price = spec == null ? goods.price() : spec.price();
        int stock = spec == null ? goods.stock() : spec.stock();
        return new CartItemView(entity.getId(), goods.id(), goods.storeId(), storeName,
                specId, specName, price, stock, entity.getQuantity(), goods);
    }
}
