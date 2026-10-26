package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.GoodsSpec;
import com.example.takeout.model.Order;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class MerchantRejectServiceTest {

    private static final long ORDER_ID = 71L;
    private static final long USER_ID = 1L;
    private static final long MERCHANT_ID = 99L;
    private static final long STORE_ID = 10L;
    private static final long GOODS_ID = 100L;
    private static final long SPEC_ID = 300L;
    private static final String ITEMS = "[{\"goodsId\":100,\"goodsName\":\"招牌饭\",\"price\":10," +
            "\"quantity\":2,\"image\":\"\",\"specId\":300,\"specName\":\"大份\",\"seckillId\":0}]";

    private final OrderDao orders = mock(OrderDao.class);
    private final StoreDao stores = mock(StoreDao.class);
    private final GoodsDao goods = mock(GoodsDao.class);
    private final CouponDao coupons = mock(CouponDao.class);
    private final UserDao users = mock(UserDao.class);
    private final GoodsSpecDao specs = mock(GoodsSpecDao.class);
    private final PaymentRecordDao payments = mock(PaymentRecordDao.class);
    private final DomainEventPublisher events = mock(DomainEventPublisher.class);
    private final OrderService service = new OrderService(orders, stores, goods, mock(AddressDao.class), coupons,
            mock(ReviewDao.class), users, mock(RefundDao.class), new ObjectMapper(), mock(CartItemMapper.class),
            mock(RiderDao.class), specs, mock(SeckillDao.class), mock(HotDataCacheService.class), events,
            mock(org.springframework.beans.factory.ObjectProvider.class), payments);

    @Test
    void itemUnavailableRejectsOnceRefundsAndDisablesOnlyTheOrderedSpec() throws Exception {
        Order paid = order(1, "", "", "", "", 0, 0);
        Order rejected = order(5, "MERCHANT", "ITEM_UNAVAILABLE", "「招牌饭(大份)」暂时缺货", "库存盘点中",
                GOODS_ID, SPEC_ID);
        when(orders.findByIdForUpdate(ORDER_ID)).thenReturn(Optional.of(paid));
        when(stores.hasMerchantAccess(MERCHANT_ID, STORE_ID)).thenReturn(true);
        when(orders.rejectByMerchant(eq(ORDER_ID), eq(MERCHANT_ID), eq("ITEM_UNAVAILABLE"),
                eq("「招牌饭(大份)」暂时缺货"), eq("库存盘点中"), eq(GOODS_ID), eq(SPEC_ID), anyString()))
                .thenReturn(true);
        when(specs.listByGoods(GOODS_ID)).thenReturn(List.of(
                new GoodsSpec(301, GOODS_ID, "小份", 8, 5, 0, 1, 1, "")));
        when(orders.findById(ORDER_ID)).thenReturn(Optional.of(rejected));

        Order.OrderView result = service.merchantReject(MERCHANT_ID, ORDER_ID, "ITEM_UNAVAILABLE",
                " 库存盘点中 ", GOODS_ID, SPEC_ID);

        assertEquals("MERCHANT", result.cancelSource());
        assertEquals("ITEM_UNAVAILABLE", result.cancelReasonCode());
        assertEquals("「招牌饭(大份)」暂时缺货", result.cancelReason());
        assertFalse(new ObjectMapper().writeValueAsString(result).contains("rejectNote"));
        verify(goods).restoreStock(GOODS_ID, 2);
        verify(specs).restoreStock(SPEC_ID, 2);
        verify(specs).disable(GOODS_ID, SPEC_ID);
        verify(goods).syncFromSpecs(GOODS_ID, 8, 5);
        verify(goods, never()).disableForStore(GOODS_ID, STORE_ID);
        verify(coupons).release(eq(66L), anyString());
        verify(users).addBalance(USER_ID, 23.0);
        verify(payments).insert(eq(ORDER_ID), eq(USER_ID), eq(23.0), eq("REFUND"), eq("BALANCE"),
                eq("SUCCESS"), anyString());
        verify(events).publish(eq(DomainEventPublisher.ORDER_CANCELLED), eq(ORDER_ID),
                argThat(payload -> "MERCHANT".equals(payload.get("source"))
                        && !payload.get("reason").toString().contains("库存盘点中")));
    }

    @Test
    void repeatedMerchantRejectReturnsPersistedResultWithoutRepeatingSideEffects() {
        Order rejected = order(5, "MERCHANT", "OTHER", "商家暂时无法接单", "", 0, 0);
        when(orders.findByIdForUpdate(ORDER_ID)).thenReturn(Optional.of(rejected));
        when(orders.findById(ORDER_ID)).thenReturn(Optional.of(rejected));
        when(stores.hasMerchantAccess(MERCHANT_ID, STORE_ID)).thenReturn(true);

        Order.OrderView result = service.merchantReject(MERCHANT_ID, ORDER_ID, null, null, null, null);

        assertEquals("OTHER", result.cancelReasonCode());
        verify(orders, never()).rejectByMerchant(anyLong(), anyLong(), anyString(), anyString(), anyString(),
                anyLong(), anyLong(), anyString());
        verify(users, never()).addBalance(anyLong(), anyDouble());
        verify(goods, never()).restoreStock(anyLong(), anyInt());
        verify(events, never()).publish(anyString(), anyLong(), anyMap());
    }

    @Test
    void rejectsUnauthorizedMerchantAndSkuOutsideTheOrder() {
        Order paid = order(1, "", "", "", "", 0, 0);
        when(orders.findByIdForUpdate(ORDER_ID)).thenReturn(Optional.of(paid));
        when(stores.hasMerchantAccess(MERCHANT_ID, STORE_ID)).thenReturn(false, true);

        assertEquals(403, assertThrows(BizException.class, () -> service.merchantReject(
                MERCHANT_ID, ORDER_ID, "OTHER", "", null, null)).getCode());
        BizException skuError = assertThrows(BizException.class, () -> service.merchantReject(
                MERCHANT_ID, ORDER_ID, "ITEM_UNAVAILABLE", "", 999L, 0L));

        assertEquals("缺货商品或规格不属于该订单", skuError.getMessage());
        verify(orders, never()).rejectByMerchant(anyLong(), anyLong(), anyString(), anyString(), anyString(),
                anyLong(), anyLong(), anyString());
    }

    @Test
    void rejectsUnknownReasonAndOrdersOutsideAwaitingAcceptance() {
        Order paid = order(1, "", "", "", "", 0, 0);
        when(orders.findByIdForUpdate(ORDER_ID)).thenReturn(Optional.of(paid));
        when(stores.hasMerchantAccess(MERCHANT_ID, STORE_ID)).thenReturn(true);
        assertEquals("拒单原因无效", assertThrows(BizException.class, () -> service.merchantReject(
                MERCHANT_ID, ORDER_ID, "BUSY", "", null, null)).getMessage());

        when(orders.findByIdForUpdate(ORDER_ID)).thenReturn(Optional.of(order(2, "", "", "", "", 0, 0)));
        assertEquals("仅待接单且资金托管中的订单可拒单", assertThrows(BizException.class,
                () -> service.merchantReject(MERCHANT_ID, ORDER_ID, "OTHER", "", null, null)).getMessage());
    }

    private static Order order(int status, String source, String code, String reason, String note,
                               long rejectGoodsId, long rejectSpecId) {
        return new Order(ORDER_ID, "NO71", USER_ID, STORE_ID, "测试店", status, ITEMS,
                "{\"addressId\":1,\"name\":\"用户\",\"phone\":\"13800138000\",\"detail\":\"地址\"}",
                20, 3, 0, 23, "", 0, status == 5 ? 2 : 0, "2026-10-26 12:00:00",
                "2026-10-26 12:01:00", "", "", status == 5 ? "2026-10-26 12:02:00" : "", "", 66,
                "DELIVERY", source, code, reason, note, rejectGoodsId, rejectSpecId, MERCHANT_ID);
    }
}
