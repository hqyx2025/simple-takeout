package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.CartItemEntity;
import com.example.takeout.model.Goods;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.mock;

class CartServiceTest {

    @Test
    void rejectsEmptyBatchDelete() {
        CartItemMapper mapper = mock(CartItemMapper.class);
        GoodsDao goodsDao = mock(GoodsDao.class);
        StoreDao storeDao = mock(StoreDao.class);
        CartService service = new CartService(mapper, goodsDao, storeDao);

        BizException exception = assertThrows(BizException.class, () -> service.deleteBatch(1L, List.of()));

        assertEquals("请选择要删除的商品", exception.getMessage());
        verify(mapper, never()).delete(any());
    }

    @Test
    void rejectsAddingOffShelfGoods() {
        CartItemMapper mapper = mock(CartItemMapper.class);
        GoodsDao goodsDao = mock(GoodsDao.class);
        StoreDao storeDao = mock(StoreDao.class);
        CartService service = new CartService(mapper, goodsDao, storeDao);
        Goods goods = new Goods(10L, 20L, "测试商品", "", 10.0, 10.0, "", 1,
                0L, 10, 0, 0, 4.5, "", 0, "now");
        when(goodsDao.findById(10L)).thenReturn(Optional.of(goods));

        BizException exception = assertThrows(BizException.class, () -> service.add(1L, 10L, 1));

        assertEquals("商品已下架，无法加入购物车", exception.getMessage());
        verify(mapper, never()).insert(any(CartItemEntity.class));
    }

    @Test
    void deleteOneIsScopedToUserAndGoods() {
        CartItemMapper mapper = mock(CartItemMapper.class);
        GoodsDao goodsDao = mock(GoodsDao.class);
        StoreDao storeDao = mock(StoreDao.class);
        CartService service = new CartService(mapper, goodsDao, storeDao);
        when(mapper.selectList(any())).thenReturn(List.of());

        List<?> result = service.deleteOne(7L, 10L);

        assertEquals(0, result.size());
        verify(mapper).delete(any());
        verify(mapper).selectList(any());
    }
}
