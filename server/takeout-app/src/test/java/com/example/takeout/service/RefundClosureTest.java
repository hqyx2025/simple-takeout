package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.example.takeout.model.*;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.example.takeout.service.thirdparty.ExternalPaymentService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Optional;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class RefundClosureTest {
    private final OrderDao orders = mock(OrderDao.class);
    private final StoreDao stores = mock(StoreDao.class);
    private final RefundDao refunds = mock(RefundDao.class);
    private final AfterSalesDao ledger = mock(AfterSalesDao.class);
    private final ExternalPaymentService payments = mock(ExternalPaymentService.class);
    private final PaymentRecordDao records = mock(PaymentRecordDao.class);
    private final AfterSalesService service = new AfterSalesService(orders, stores, refunds, ledger, payments,
            records, mock(DomainEventPublisher.class), new ObjectMapper());
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static BigDecimal amount(String value) { return new BigDecimal(value); }
    private static String now() { return LocalDateTime.now().format(TIME); }

    @BeforeEach
    void amounts() {
        when(refunds.refundedAmount(7)).thenReturn(amount("0.00"));
        when(refunds.merchantRefunded(7)).thenReturn(amount("0.00"));
        when(stores.findById(3)).thenReturn(Optional.of(new Store(3, "店铺", "", 4.5, 0, 3, 0,
                "", "", "[]", "", 1, "[]", 4, 1, 0, "")));
    }

    private Order order(int status, int escrow, int reviewed, String delivered) {
        return new Order(7, "NO7", 2, 3, "店铺", status, "[]", "{}", 10, 3, 0, 13, "", reviewed,
                escrow, now(), now(), "", "", delivered, "", 0);
    }

    private RefundRecord record(String status, int escrow, String value, int appeals) {
        return new RefundRecord(9, 7, 2, 4, "QUALITY_ISSUE", "汤洒了", amount(value), status, now(), now(), "无法核实",
                List.of("/uploads/food.jpg"), List.of(), "", appeals, "", List.of(), escrow, escrow,
                amount("0.00"), amount("0.00"), null);
    }

    @Test
    void capabilitiesAndApplicationBothRejectNewRequestsAfterARejection() {
        Order delivered = order(4, 1, 1, now());
        when(refunds.latestByOrder(7)).thenReturn(Optional.of(record("REJECTED", 1, "3.00", 0)));
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(delivered));
        assertFalse(service.canApply(delivered));
        assertTrue(assertThrows(BizException.class, () -> service.apply(2, 7, "OTHER", "补充",
                "new-application-key", amount("3.00"), List.of())).getMessage().contains("申诉"));
        verify(ledger, never()).markPending(anyLong(), anyInt());
    }

    @Test
    void ownershipPrecedesReplayAndHistory() {
        when(orders.findById(7)).thenReturn(Optional.of(order(4, 0, 0, now())));
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(6, 2, 1, now())));
        assertEquals(403, assertThrows(BizException.class, () -> service.history(99, 7)).getCode());
        assertEquals(403, assertThrows(BizException.class,
                () -> service.apply(99, 7, "OTHER", "餐损", "key", null, List.of())).getCode());
        verify(refunds, never()).findByRequestKey(anyLong(), anyString());
    }

    @Test
    void processedAndPendingReplayDoNotRevalidateNewPayload() {
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(6, 2, 1, now())));
        for (String status : List.of("REJECTED", "REFUNDED")) {
            when(refunds.findByRequestKey(7, "key")).thenReturn(Optional.of(record(status, 0, "13.00", 0)));
            assertEquals(status, service.apply(2, 7, "invalid", "", " key ", amount("99.00"), List.of()).status());
        }
        when(refunds.findPending(7)).thenReturn(Optional.of(record("PENDING", 0, "13.00", 0)));
        assertEquals(9, service.apply(2, 7, "OTHER", "餐损", "alias", null, List.of()).id());
        verify(refunds).bindApplyRequest(7, "alias", 9);
        verifyNoInteractions(ledger);
    }

    @Test
    void settledReviewedOrdersAllowPartialRefundWithin48Hours() {
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(4, 1, 1, now())));
        when(ledger.markPending(7, 1)).thenReturn(true);
        when(refunds.insertAfterSales(eq(7L), eq(2L), eq(4L), eq("OTHER"), eq("餐损"), eq(amount("2.25")),
                anyString(), eq("key"), eq("[\"/uploads/food.jpg\"]"), eq(1))).thenReturn(9L);
        when(refunds.findById(9)).thenReturn(Optional.of(record("PENDING", 1, "2.25", 0)));
        assertEquals(amount("2.25"), service.apply(2, 7, "OTHER", " 餐损 ", "key", amount("2.25"), List.of("/uploads/food.jpg")).amount());
        verify(refunds).bindApplyRequest(7, "key", 9);
    }

    @Test
    void windowAndAmountAndEvidenceAreValidated() {
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(4, 0, 0, LocalDateTime.now().minusHours(49).format(TIME))));
        assertThrows(BizException.class, () -> service.apply(2, 7, "OTHER", "餐损", null, null, List.of()));
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(4, 0, 1, now())));
        when(refunds.refundedAmount(7)).thenReturn(amount("10.00"));
        for (String value : List.of("0", "-1", "3.01", "1.001"))
            assertThrows(BizException.class, () -> service.apply(2, 7, "OTHER", "餐损", null, amount(value), List.of()));
        assertThrows(BizException.class, () -> service.apply(2, 7, "OTHER", "餐损", null, amount("1.00"), List.of("https://example.com/food.jpg")));
        assertThrows(BizException.class, () -> service.apply(2, 7, "OTHER", "", null, amount("1.00"), List.of()));
        assertNull(service.eligibleUntil(order(1, 0, 0, "")));
        verifyNoInteractions(ledger);
    }

    @Test
    void settledRefundCapsMerchantResponsibilityAndPreservesPartialSettlement() {
        Order order = order(6, 1, 1, now());
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order));
        when(refunds.findById(9)).thenReturn(Optional.of(record("PENDING", 1, "5.00", 0)));
        when(refunds.findByIdForUpdate(9)).thenReturn(Optional.of(record("PENDING", 1, "5.00", 0)));
        when(refunds.merchantRefunded(7)).thenReturn(amount("8.00"));
        when(refunds.refundedAmount(7)).thenReturn(amount("8.00"));
        when(ledger.deductMerchant(4, amount("2.00"))).thenReturn(amount("0.75"));
        when(payments.refundOriginalPayment(order, amount("5.00"), 9, true)).thenReturn("BALANCE");
        when(refunds.complete(eq(9L), eq(amount("2.00")), eq(amount("3.00")), anyString())).thenReturn(true);
        when(ledger.finishOrder(7, 1, true)).thenReturn(true);
        service.approve(9);
        verify(ledger).insertLedger(eq(9L), eq(7L), eq(4L), eq(amount("2.00")), eq(amount("0.75")), eq(amount("1.25")), eq(amount("3.00")), anyString());
        verify(ledger).creditCustomer(2, amount("5.00"));
        verify(records).insert(eq(7L), eq(2L), eq(amount("5.00")), eq("REFUND"), eq("BALANCE"), eq("SUCCESS"), anyString());
        var sequence = inOrder(orders, refunds);
        sequence.verify(refunds).findById(9);
        sequence.verify(orders).findByIdForUpdate(7);
        sequence.verify(refunds).findByIdForUpdate(9);
    }

    @Test
    void unsettledPartialRefundDoesNotDebitMerchantWallet() {
        Order order = order(6, 0, 1, now());
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order));
        when(refunds.findById(9)).thenReturn(Optional.of(record("PENDING", 0, "2.00", 0)));
        when(refunds.findByIdForUpdate(9)).thenReturn(Optional.of(record("PENDING", 0, "2.00", 0)));
        when(payments.refundOriginalPayment(order, amount("2.00"), 9, false)).thenReturn("ALIPAY");
        when(refunds.complete(eq(9L), eq(amount("2.00")), eq(amount("0.00")), anyString())).thenReturn(true);
        when(ledger.finishOrder(7, 0, false)).thenReturn(true);
        service.approve(9);
        verify(ledger, never()).deductMerchant(anyLong(), any());
        verify(ledger, never()).creditCustomer(anyLong(), any());
        verify(ledger).finishOrder(7, 0, false);
    }

    @Test
    void rejectionRestoresOriginalEscrowAndOnlyOneAppealIsAllowed() {
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(6, 1, 1, now())));
        when(refunds.findById(9)).thenReturn(Optional.of(record("PENDING", 1, "3.00", 0)));
        when(refunds.findByIdForUpdate(9)).thenReturn(Optional.of(record("PENDING", 1, "3.00", 0)));
        when(refunds.updateStatus(eq(9L), eq("REJECTED"), anyString(), eq("请补充说明"))).thenReturn(true);
        when(ledger.finishOrder(7, 1, false)).thenReturn(true);
        service.reject(9, " 请补充说明 ");
        var sequence = inOrder(orders, refunds);
        sequence.verify(refunds).findById(9);
        sequence.verify(orders).findByIdForUpdate(7);
        sequence.verify(refunds).findByIdForUpdate(9);
        when(orders.findByIdForUpdate(7)).thenReturn(Optional.of(order(4, 1, 1, LocalDateTime.now().minusHours(72).format(TIME))));
        when(refunds.findByIdForUpdate(9)).thenReturn(Optional.of(record("REJECTED", 1, "3.00", 0)));
        when(ledger.markPending(7, 1)).thenReturn(true);
        when(refunds.appeal(eq(9L), eq("补充照片"), eq("[]"), eq(1), anyString())).thenReturn(true);
        service.appeal(2, 7, 9, "补充照片", List.of());
        when(refunds.findByIdForUpdate(9)).thenReturn(Optional.of(record("REJECTED", 1, "3.00", 1)));
        assertThrows(BizException.class, () -> service.appeal(2, 7, 9, "再申诉", List.of()));
    }
}
