package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.example.takeout.mapper.CartItemMapper;
import com.example.takeout.model.Order;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.model.Store;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class RefundClosureTest {
    private final OrderDao orders = mock(OrderDao.class);
    private final StoreDao stores = mock(StoreDao.class);
    private final RefundDao refunds = mock(RefundDao.class);
    private final OrderService service = new OrderService(orders, stores, mock(GoodsDao.class), mock(AddressDao.class),
            mock(CouponDao.class), mock(ReviewDao.class), mock(UserDao.class), refunds, new ObjectMapper(),
            mock(CartItemMapper.class), mock(RiderDao.class), mock(GoodsSpecDao.class), mock(SeckillDao.class),
            mock(HotDataCacheService.class), mock(DomainEventPublisher.class),
            mock(org.springframework.beans.factory.ObjectProvider.class), mock(PaymentRecordDao.class));

    private Order order(int status, int escrow, int reviewed) {
        return new Order(7, "NO7", 2, 3, "店铺", status, "[]", "{}", 10, 3, 0, 13, "", reviewed,
                escrow, "2026-10-26 10:00:00", "", "", "", "", "", 0);
    }

    private RefundRecord record(String status) {
        return new RefundRecord(9, 7, 2, 4, "QUALITY_ISSUE", "汤洒了", 13, status, "", "", "");
    }

    @Test
    void historyAndReplayValidateOwnerBeforeReadingRefunds() {
        when(orders.findById(7)).thenReturn(Optional.of(order(4, 0, 0)));
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(6, 2, 0)));
        assertEquals(403, assertThrows(BizException.class, () -> service.refundHistory(99, 7)).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> service.applyRefund(99, 7, "OTHER", "餐损", "key")).getCode());
        verifyNoInteractions(refunds);
        when(refunds.listByOrder(7)).thenReturn(List.of(record("REJECTED")));
        assertEquals("REJECTED", service.refundHistory(2, 7).getFirst().status());
    }

    @Test
    void keyReplayReturnsProcessedResultBeforeCurrentEligibilityOrReasonValidation() {
        for (String status : List.of("REJECTED", "REFUNDED")) {
            when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(6, 2, 1)));
            when(refunds.findByRequestKey(7, "key")).thenReturn(Optional.of(record(status)));
            assertEquals(status, service.applyRefund(2, 7, "invalid", "", " key ").status());
        }
        verify(refunds, never()).findPending(anyLong());
        verify(orders, never()).markRefunding(anyLong());
    }

    @Test
    void pendingRequestIsReturnedInsteadOfCreatingASecondApplication() {
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(6, 0, 0)));
        when(refunds.findPending(7)).thenReturn(Optional.of(record("PENDING")));
        assertEquals(9, service.applyRefund(2, 7, "OTHER", "新问题", "new-key").id());
        verify(refunds).bindApplyRequest(7, "new-key", 9);
        verify(orders, never()).markRefunding(anyLong());
    }

    @Test
    void otherRequiresExplanationAndTrimsBeforePersistence() {
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(4, 0, 0)));
        for (String reason : new String[]{null, "", " \t\n "}) {
            assertEquals("选择其他原因时，请说明具体问题", assertThrows(BizException.class,
                    () -> service.applyRefund(2, 7, "OTHER", reason, "key")).getMessage());
        }
        when(orders.markRefunding(7)).thenReturn(true);
        when(stores.findById(3)).thenReturn(Optional.of(new Store(3, "店铺", "", 4.5, 0, 3, 0,
                "", "", "[]", "", 1, "[]", 4, 1, 0, "")));
        when(refunds.insert(eq(7L), eq(2L), eq(4L), eq("OTHER"), eq("汤洒了"), eq(13d), anyString(), eq("key")))
                .thenReturn(9L);
        when(refunds.findById(9)).thenReturn(Optional.of(record("PENDING")));
        assertEquals(9, service.applyRefund(2, 7, "OTHER", "  汤洒了  ", "key").id());
        verify(refunds).bindApplyRequest(7, "key", 9);
        verify(refunds).insert(eq(7L), eq(2L), eq(4L), eq("OTHER"), eq("汤洒了"), eq(13d), anyString(), eq("key"));
    }

    @Test
    void refundCannotStartAfterSettlementOrReviewAndKeysAreLengthLimited() {
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(4, 0, 0)));
        assertEquals("退款请求标识最多 128 个字符", assertThrows(BizException.class,
                () -> service.applyRefund(2, 7, "OTHER", "餐损", "x".repeat(129))).getMessage());
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(4, 1, 0)));
        assertThrows(BizException.class, () -> service.applyRefund(2, 7, "OTHER", "餐损", "key"));
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(4, 0, 1)));
        assertThrows(BizException.class, () -> service.applyRefund(2, 7, "OTHER", "餐损", "key"));
        verify(orders, never()).markRefunding(anyLong());
    }

    @Test
    void adminRejectionRequiresTrimmedReasonWithinStorageLimit() {
        AdminService admin = new AdminService(stores, orders, mock(UserDao.class), mock(GoodsDao.class), refunds,
                service, mock(AdminStatsDao.class), mock(HotDataCacheService.class),
                mock(DomainEventPublisher.class), mock(PaymentRecordDao.class));
        for (String reason : new String[]{null, "", "  ", "理".repeat(256)}) {
            assertThrows(BizException.class, () -> admin.rejectRefund(9, reason));
        }
        verifyNoInteractions(refunds);
        when(refunds.findByIdForUpdate(9)).thenReturn(Optional.of(record("PENDING")));
        when(refunds.updateStatus(eq(9L), eq("REJECTED"), anyString(), eq("请补充说明"))).thenReturn(true);
        when(refunds.findById(9)).thenReturn(Optional.of(record("REJECTED")));
        admin.rejectRefund(9, "  请补充说明  ");
        verify(refunds).updateStatus(eq(9L), eq("REJECTED"), anyString(), eq("请补充说明"));
    }
}
