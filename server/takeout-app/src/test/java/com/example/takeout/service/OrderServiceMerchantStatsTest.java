package com.example.takeout.service;

import com.example.takeout.dao.*;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.Store;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderServiceMerchantStatsTest {

    private final OrderDao orders = mock(OrderDao.class);
    private final StoreDao stores = mock(StoreDao.class);
    private final OrderService service = new OrderService(orders, stores, mock(GoodsDao.class),
            mock(AddressDao.class), mock(CouponDao.class), mock(ReviewDao.class), mock(UserDao.class),
            mock(RefundDao.class), new ObjectMapper(), mock(CartItemMapper.class), mock(RiderDao.class),
            mock(GoodsSpecDao.class), mock(SeckillDao.class), mock(HotDataCacheService.class),
            mock(DomainEventPublisher.class), mock(ObjectProvider.class), mock(PaymentRecordDao.class));

    @Test
    void merchantStatsUsesAggregateQueryAndMapsChartData() {
        Store store = new Store(12, "店铺", "", 5, 0, 3, 20, "30分钟", "未知距离", "", "",
                1, "[]", 7, 1, 0, "2026-01-01 00:00:00");
        when(stores.listByOwner(7)).thenReturn(List.of(store));
        List<Double> revenue = List.of(1d, 2d, 3d, 4d, 5d, 6d, 7d);
        List<Long> statuses = List.of(1L, 2L, 3L, 4L, 5L);
        when(orders.aggregateMerchantStats(any(Long.class), any(String.class), any(String.class), any(String.class),
                any(String.class), any(List.class))).thenReturn(new OrderDao.MerchantStatsAggregate(
                8, 10.5d, 3, 16, 20.5d, 5, 30, 40.5d, 9, 99, 100.5d, revenue, statuses));

        OrderService.MerchantStats stats = service.merchantStats(7, 12);

        assertEquals(3, stats.todayCount());
        assertEquals(8, stats.todayOrderCount());
        assertEquals(99, stats.totalCount());
        assertEquals(revenue, stats.weekRevenue());
        assertEquals(statuses, stats.todayStatus());
        verify(orders).aggregateMerchantStats(any(Long.class), any(String.class), any(String.class), any(String.class),
                any(String.class), any(List.class));
    }
}
