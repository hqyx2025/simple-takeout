package com.example.takeout.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.example.takeout.common.BizException;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.CartItemEntity;
import com.example.takeout.model.CartItemView;
import com.example.takeout.model.Goods;
import com.example.takeout.model.Store;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * 购物车业务：每个用户只能操作自己的购物车，商品详情由现有 JdbcTemplate DAO 查询。
 */
@Service
public class CartService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final CartItemMapper cartItemMapper;
    private final GoodsDao goodsDao;
    private final StoreDao storeDao;

    public CartService(CartItemMapper cartItemMapper, GoodsDao goodsDao, StoreDao storeDao) {
        this.cartItemMapper = cartItemMapper;
        this.goodsDao = goodsDao;
        this.storeDao = storeDao;
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
            result.add(toView(entity, goods));
        }
        return result;
    }

    @Transactional
    public List<CartItemView> add(long userId, long goodsId, int quantity) {
        requirePositiveQuantity(quantity);
        Goods goods = requireAvailableGoods(goodsId);
        CartItemEntity existing = findEntity(userId, goodsId);
        int nextQuantity = existing == null ? quantity : existing.getQuantity() + quantity;
        validateStock(goods, nextQuantity);
        saveQuantity(userId, goodsId, nextQuantity, existing);
        return list(userId);
    }

    @Transactional
    public List<CartItemView> setQuantity(long userId, long goodsId, int quantity) {
        if (quantity <= 0) {
            return deleteOne(userId, goodsId);
        }
        Goods goods = requireAvailableGoods(goodsId);
        validateStock(goods, quantity);
        saveQuantity(userId, goodsId, quantity, findEntity(userId, goodsId));
        return list(userId);
    }

    @Transactional
    public List<CartItemView> deleteOne(long userId, long goodsId) {
        cartItemMapper.delete(new LambdaQueryWrapper<CartItemEntity>()
                .eq(CartItemEntity::getUserId, userId)
                .eq(CartItemEntity::getGoodsId, goodsId));
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

    private CartItemEntity findEntity(long userId, long goodsId) {
        return cartItemMapper.selectOne(new LambdaQueryWrapper<CartItemEntity>()
                .eq(CartItemEntity::getUserId, userId)
                .eq(CartItemEntity::getGoodsId, goodsId)
                .last("LIMIT 1"));
    }

    private void saveQuantity(long userId, long goodsId, int quantity, CartItemEntity existing) {
        String now = LocalDateTime.now().format(FMT);
        if (existing == null) {
            CartItemEntity entity = new CartItemEntity();
            entity.setUserId(userId);
            entity.setGoodsId(goodsId);
            entity.setQuantity(quantity);
            entity.setCreateTime(now);
            entity.setUpdateTime(now);
            cartItemMapper.insert(entity);
            return;
        }
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

    private void validateStock(Goods goods, int quantity) {
        if (quantity > goods.stock()) {
            throw new BizException("商品库存不足，当前最多可选 " + goods.stock() + " 份");
        }
    }

    private void requirePositiveQuantity(int quantity) {
        if (quantity <= 0) {
            throw new BizException("商品数量必须大于 0");
        }
    }

    private CartItemView toView(CartItemEntity entity, Goods goods) {
        String storeName = storeDao.findById(goods.storeId()).map(Store::name).orElse("店铺");
        return new CartItemView(entity.getId(), goods.id(), goods.storeId(), storeName,
                entity.getQuantity(), goods);
    }
}
