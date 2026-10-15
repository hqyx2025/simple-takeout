package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AdminStatsDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.MarketingActivity;
import com.example.takeout.model.Seckill;
import com.example.takeout.service.mq.DomainEventPublisher;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminServiceMarketingTest {

    private final StoreDao stores = mock(StoreDao.class);
    private final SeckillDao seckills = mock(SeckillDao.class);
    private final HotDataCacheService cache = mock(HotDataCacheService.class);
    private final AdminService service = new AdminService(stores, mock(OrderDao.class), mock(UserDao.class),
            mock(GoodsDao.class), mock(RefundDao.class), mock(OrderService.class), mock(AdminStatsDao.class),
            cache, mock(DomainEventPublisher.class), mock(PaymentRecordDao.class), seckills);

    @BeforeEach
    void resetMocks() {
        org.mockito.Mockito.reset(stores, seckills, cache);
    }

    @Test
    void forwardsStoreAndStatusFiltersToBothMarketingLists() {
        when(stores.listMarketingActivitiesForAdmin(12L, 1)).thenReturn(List.of());
        when(seckills.listForAdmin(12L, 0)).thenReturn(List.of());

        service.marketingActivities(12L, 1);
        service.seckills(12L, 0);

        verify(stores).listMarketingActivitiesForAdmin(12L, 1);
        verify(seckills).listForAdmin(12L, 0);
    }

    @Test
    void rejectsInvalidStatusFilters() {
        assertEquals("活动状态筛选不合法", assertThrows(BizException.class,
                () -> service.marketingActivities(null, 2)).getMessage());
        assertEquals("秒杀状态筛选不合法", assertThrows(BizException.class,
                () -> service.seckills(null, -1)).getMessage());
    }

    @Test
    void rejectsDeletingSeckillThatHasSales() {
        when(seckills.findById(7)).thenReturn(Optional.of(seckill(7, 2)));

        BizException error = assertThrows(BizException.class, () -> service.deleteSeckill(7));

        assertEquals("已有销量的秒杀不可删除，请先下架", error.getMessage());
        verify(seckills, never()).deleteIfUnsold(7);
        verify(cache, never()).evictByPattern(org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void rejectsSeckillDeletionWhenSalesRaceWithTheAdminRequest() {
        when(seckills.findById(7)).thenReturn(Optional.of(seckill(7, 0)));
        when(seckills.deleteIfUnsold(7)).thenReturn(false);

        BizException error = assertThrows(BizException.class, () -> service.deleteSeckill(7));

        assertEquals("秒杀状态已变化，请刷新后重试", error.getMessage());
        verify(cache, never()).evictByPattern(org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void deletesUnsoldSeckillAndInvalidatesCaches() {
        when(seckills.findById(7)).thenReturn(Optional.of(seckill(7, 0)));
        when(seckills.deleteIfUnsold(7)).thenReturn(true);

        service.deleteSeckill(7);

        verify(seckills).deleteIfUnsold(7);
        for (String pattern : HotDataCacheService.Keys.STORE_GOODS_PATTERNS) {
            verify(cache).evictByPattern(pattern);
        }
    }

    @Test
    void statusChangeInvalidatesStoreAndGoodsCaches() {
        when(stores.findMarketingActivityById(3)).thenReturn(Optional.of(activity(3, 1)),
                Optional.of(activity(3, 0)));

        MarketingActivity result = service.updateMarketingActivityStatus(3, 0);

        assertEquals(0, result.status());
        verify(stores).updateMarketingActivityStatus(3, 0);
        for (String pattern : HotDataCacheService.Keys.STORE_GOODS_PATTERNS) {
            verify(cache).evictByPattern(pattern);
        }
    }

    private MarketingActivity activity(long id, int status) {
        return new MarketingActivity(id, 1, "DISCOUNT", "活动", 0.8, 0, 0, 0,
                "2026-01-01 00:00:00", "2026-12-31 23:59:59", status, "2026-01-01 00:00:00");
    }

    private Seckill seckill(long id, int sold) {
        return new Seckill(id, 1, 1, 9.9, 10, sold, "2026-01-01 00:00:00",
                "2026-12-31 23:59:59", 1, "2026-01-01 00:00:00");
    }
}
