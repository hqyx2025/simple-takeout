package com.example.takeout.service.thirdparty;

import com.example.takeout.common.BizException;
import com.example.takeout.config.PaymentProperties;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.PaymentTransactionDao;
import com.example.takeout.model.Order;
import com.example.takeout.model.PaymentTransaction;
import com.example.takeout.service.mq.DomainEventPublisher;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.doThrow;

class ExternalPaymentServiceTest {

    private final PaymentProperties properties = new PaymentProperties();
    private final PaymentGateway gateway = mock(PaymentGateway.class);
    private final PaymentTransactionDao transactionDao = mock(PaymentTransactionDao.class);
    private final OrderDao orderDao = mock(OrderDao.class);
    private final PaymentRecordDao paymentRecordDao = mock(PaymentRecordDao.class);
    private final DomainEventPublisher eventPublisher = mock(DomainEventPublisher.class);
    private ExternalPaymentService service;

    @BeforeEach
    void setUp() {
        properties.setRealEnabled(true);
        productionMode();
        properties.getAlipay().setAppPrivateKey("mock-private-key");
        properties.getAlipay().setPublicKey("mock-public-key");
        properties.getAlipay().setNotifyUrl("https://callback.example/api/payment/alipay/notify");
        when(gateway.channel()).thenReturn(PaymentChannels.ALIPAY);
        when(transactionDao.findByOutTradeNoForUpdate(anyString())).thenAnswer(invocation ->
                transactionDao.findByOutTradeNo(invocation.getArgument(0)));
        service = new ExternalPaymentService(properties, List.of(gateway), transactionDao, orderDao,
                paymentRecordDao, eventPublisher);
        var attempts = mock(com.example.takeout.service.ExternalRefundAttemptService.class);
        when(attempts.prepare(anyString(), any(), anyLong(), anyString(), any(), any(), any())).thenAnswer(invocation -> {
            PaymentTransaction payment = invocation.getArgument(1);
            return new com.example.takeout.service.ExternalRefundAttemptService.Attempt(invocation.getArgument(3),
                    invocation.getArgument(0), payment.orderId(), payment.id(), invocation.getArgument(2), payment.channel(),
                    payment.outTradeNo(), "", invocation.getArgument(4), payment.amount(), "null", "REQUESTED");
        });
        service.configureRefundAttempts(attempts);
        PlatformTransactionManager manager = mock(PlatformTransactionManager.class);
        when(manager.getTransaction(any())).thenAnswer(invocation -> new SimpleTransactionStatus());
        service.configureTransactions(new TransactionTemplate(manager));
    }

    @Test
    void sandboxAppPaymentWorksWithoutEnablingProductionPayments() {
        properties.setSandbox(true);
        properties.getAlipay().setGatewayUrl("https://openapi-sandbox.dl.alipaydev.com/gateway.do");
        properties.setRealEnabled(false);
        properties.setMockEnabled(false);
        paymentFixture(null);
        when(gateway.createAppPayment(anyString(), anyString(), any(), any())).thenReturn("sandbox-app-order");
        var launch = service.startPayment("ALIPAY", pendingOrder(), "APP");
        assertEquals("APP", launch.paymentMode());
        assertEquals("sandbox-app-order", launch.appOrderInfo());
        assertTrue(launch.paymentSandbox());
        verify(gateway).createAppPayment(anyString(), anyString(), any(), any());
        verify(gateway, never()).createQrPayment(anyString(), anyString(), any(), any());
    }

    @Test
    void explicitMockModeStillBlocksSandboxProviderPayments() {
        properties.setRealEnabled(false);
        properties.setMockEnabled(true);

        BizException error = assertThrows(BizException.class,
                () -> service.startPayment("ALIPAY", pendingOrder(), "APP"));

        assertEquals(503, error.getCode());
        verify(orderDao, never()).findByIdForUpdate(anyLong());
        verify(gateway, never()).createAppPayment(anyString(), anyString(), any(), any());
    }

    @Test
    void rejectsUnknownModeBeforeStartingProviderPayment() {
        assertThrows(BizException.class, () -> service.startPayment("ALIPAY", pendingOrder(), "WEB"));
        verify(orderDao, never()).findByIdForUpdate(anyLong());
    }

    @Test
    void productionAppReturnsSignedOrderWithoutCreatingQrAndRestoresSamePayload() {
        productionMode();
        var active = paymentFixture(null);
        when(gateway.createAppPayment(anyString(), anyString(), any(), any())).thenReturn("app_id=signed-app-order");

        ExternalPaymentService.PaymentLaunch launch = service.startPayment("ALIPAY", pendingOrder(), "APP");
        assertEquals("", launch.paymentUrl());
        assertEquals("app_id=signed-app-order", launch.appOrderInfo());
        assertEquals("APP", launch.paymentMode());
        assertTrue(!launch.paymentSandbox());
        assertEquals(launch, service.startPayment("ALIPAY", pendingOrder(), "APP"));
        when(transactionDao.findLatestByOrder(7)).thenReturn(Optional.of(active.get()));
        assertEquals(launch, service.paymentDetails(7));
        verify(gateway, org.mockito.Mockito.times(1)).createAppPayment(anyString(), anyString(), any(), any());
        verify(gateway, never()).createQrPayment(anyString(), anyString(), any(), any());
        verify(orderDao, never()).markPaid(anyLong(), anyString());
    }

    @Test
    void appToQrClosesAndConfirmsPreviousTradeBeforeCreatingFreshQrTrade() {
        productionMode();
        paymentFixture(appPayment("PENDING"));
        when(gateway.query("ALI123")).thenReturn(new PaymentGateway.QueryResult(false, false, null),
                new PaymentGateway.QueryResult(false, true, null));
        when(gateway.createQrPayment(anyString(), anyString(), any(), any())).thenReturn("https://qr.alipay.test/new");

        var launch = service.startPayment("ALIPAY", pendingOrder(), "QR");
        assertEquals("QR", launch.paymentMode());
        assertEquals("https://qr.alipay.test/new", launch.paymentUrl());
        assertTrue(!"ALI123".equals(launch.outTradeNo()));
        var sequence = inOrder(gateway, transactionDao);
        sequence.verify(gateway).query("ALI123");
        sequence.verify(gateway).close("ALI123");
        sequence.verify(gateway).query("ALI123");
        sequence.verify(transactionDao).markClosed(9);
        sequence.verify(transactionDao).insertPending(eq(7L), eq(2L), eq("ALIPAY"), eq(new BigDecimal("13.00")),
                anyString(), anyString(), eq("QR"));
        sequence.verify(gateway).createQrPayment(eq(launch.outTradeNo()), anyString(), any(), any());
    }

    @Test
    void uncertainAppCloseKeepsOriginalAttemptAndDoesNotCreateQr() {
        productionMode();
        paymentFixture(appPayment("PENDING"));
        when(gateway.query("ALI123")).thenReturn(new PaymentGateway.QueryResult(false, false, null));
        assertThrows(BizException.class, () -> service.startPayment("ALIPAY", pendingOrder(), "QR"));
        verify(transactionDao, never()).markClosed(anyLong());
        verify(gateway, never()).createQrPayment(anyString(), anyString(), any(), any());
    }

    @Test
    void modeSwitchSettlesAlreadyPaidAppInsteadOfCreatingAnotherCharge() {
        productionMode();
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(pendingOrder()), Optional.of(pendingOrder()),
                Optional.of(order(1)));
        when(transactionDao.findActiveByOrder(7)).thenReturn(Optional.of(appPayment("PENDING")));
        when(transactionDao.findByOutTradeNo("ALI123")).thenReturn(Optional.of(appPayment("PENDING")));
        when(transactionDao.findSuccessfulByOrder(7)).thenReturn(Optional.of(appPayment("SUCCESS")));
        when(gateway.query("ALI123")).thenReturn(new PaymentGateway.QueryResult(true, false,
                new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1300, "CNY", true)));
        when(orderDao.markPaid(eq(7L), anyString())).thenReturn(true);
        when(transactionDao.markSuccess(eq(9L), eq("provider-1"), anyString())).thenReturn(true);

        assertEquals("SUCCESS", service.startPayment("ALIPAY", pendingOrder(), "QR").status());
        verify(gateway, never()).close(anyString());
        verify(gateway, never()).createQrPayment(anyString(), anyString(), any(), any());
    }

    @Test
    void oldClosedAppPayloadPaidAfterSwitchIsRefundedAndNeverAdvancesOrder() {
        productionMode();
        when(gateway.verifyNotification("raw", Map.of())).thenReturn(
                new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1300, "CNY", true));
        when(transactionDao.findByOutTradeNo("ALI123")).thenReturn(Optional.of(appPayment("CLOSED")));
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(pendingOrder()));
        assertEquals(ExternalPaymentService.NotificationResult.REFUNDED,
                service.acceptNotification("ALIPAY", "raw", Map.of()));
        verify(gateway).refund("ALI123", "RALI123", new BigDecimal("13.00"), new BigDecimal("13.00"));
        verify(orderDao, never()).markPaid(anyLong(), anyString());
    }

    @Test
    void rejectsInvalidSignatureBeforeReadingOrUpdatingPayment() {
        when(gateway.verifyNotification("raw", Map.of("signature", "bad")))
                .thenThrow(new SecurityException("bad signature"));

        assertThrows(SecurityException.class,
                () -> service.acceptNotification(PaymentChannels.ALIPAY, "raw", Map.of("signature", "bad")));

        verify(transactionDao, never()).findByOutTradeNo(anyString());
        verify(orderDao, never()).markPaid(anyLong(), anyString());
        verify(paymentRecordDao, never()).insert(anyLong(), anyLong(), anyDouble(),
                anyString(), anyString(), anyString(), anyString());
    }

    @Test
    void rejectsAmountMismatchAfterSignatureVerification() {
        when(gateway.verifyNotification("raw", Map.of())).thenReturn(
                new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1299, "CNY", true));
        when(transactionDao.findByOutTradeNo("ALI123")).thenReturn(Optional.of(payment("PENDING", null)));

        assertThrows(SecurityException.class,
                () -> service.acceptNotification(PaymentChannels.ALIPAY, "raw", Map.of()));

        verify(orderDao, never()).findById(anyLong());
    }

    @Test
    void verifiesThenSettlesPendingOrderAndRecordsProviderTransaction() {
        when(gateway.verifyNotification("raw", Map.of())).thenReturn(
                new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1300, "CNY", true));
        when(transactionDao.findByOutTradeNo("ALI123")).thenReturn(Optional.of(payment("PENDING", null)));
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(pendingOrder()));
        when(orderDao.markPaid(eq(7L), anyString())).thenReturn(true);
        when(transactionDao.markSuccess(eq(9L), eq("provider-1"), anyString())).thenReturn(true);

        assertEquals(ExternalPaymentService.NotificationResult.PAID,
                service.acceptNotification(PaymentChannels.ALIPAY, "raw", Map.of()));

        verify(orderDao).markPaid(eq(7L), anyString());
        verify(transactionDao).markSuccess(eq(9L), eq("provider-1"), anyString());
        verify(paymentRecordDao).insert(eq(7L), eq(2L), eq(13.0), eq("PAY"), eq("ALIPAY"), eq("SUCCESS"), anyString());
        verify(eventPublisher).publish(eq(DomainEventPublisher.ORDER_PAID), eq(7L), any());
    }

    @Test
    void treatsRepeatedVerifiedNotificationAsIdempotent() {
        when(gateway.verifyNotification("raw", Map.of())).thenReturn(
                new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1300, "CNY", true));
        when(transactionDao.findByOutTradeNo("ALI123"))
                .thenReturn(Optional.of(payment("SUCCESS", "provider-1")));

        assertEquals(ExternalPaymentService.NotificationResult.DUPLICATE,
                service.acceptNotification(PaymentChannels.ALIPAY, "raw", Map.of()));

        verify(orderDao, never()).findById(anyLong());
        verify(paymentRecordDao, never()).insert(anyLong(), anyLong(), anyDouble(),
                anyString(), anyString(), anyString(), anyString());
    }

    @Test
    void refundsLateVerifiedChargeForCancelledOrderInsteadOfMarkingItPaid() {
        when(gateway.verifyNotification("raw", Map.of())).thenReturn(
                new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1300, "CNY", true));
        when(transactionDao.findByOutTradeNo("ALI123")).thenReturn(Optional.of(payment("PENDING", null)));
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(order(5)));

        assertEquals(ExternalPaymentService.NotificationResult.REFUNDED,
                service.acceptNotification(PaymentChannels.ALIPAY, "raw", Map.of()));

        verify(orderDao, never()).markPaid(anyLong(), anyString());
        verify(transactionDao, never()).markSuccess(anyLong(), anyString(), anyString());
        verify(gateway).refund("ALI123", "RALI123", new BigDecimal("13.00"), new BigDecimal("13.00"));
        verify(transactionDao).markLateRefunded(eq(9L), eq("provider-1"), anyString());
    }

    @Test
    void doesNotStartProviderPaymentWhenRealModeIsDisabled() {
        properties.setRealEnabled(false);
        assertThrows(BizException.class, () -> service.startPayment(PaymentChannels.ALIPAY, pendingOrder()));
        verify(gateway, never()).createQrPayment(anyString(), anyString(), any(), any());
    }

    @Test
    void reusesAnExistingPendingAttemptInsteadOfCreatingAnotherCharge() {
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(pendingOrder()));
        when(transactionDao.findActiveByOrder(7)).thenReturn(Optional.of(payment("PENDING", null)));

        ExternalPaymentService.PaymentLaunch launch = service.startPayment(PaymentChannels.ALIPAY, pendingOrder());

        assertEquals("ALI123", launch.outTradeNo());
        assertEquals("https://qr.alipay.test/pay", launch.paymentUrl());
        verify(transactionDao, never()).insertPending(anyLong(), anyLong(), anyString(), any(), anyString(), anyString());
        verify(gateway, never()).createQrPayment(anyString(), anyString(), any(), any());
    }

    @Test
    void closedThirdPartyAttemptDoesNotLabelALaterBalancePaymentAsAlipay() {
        when(transactionDao.findLatestByOrder(7)).thenReturn(Optional.of(payment("CLOSED", null)));

        assertNull(service.paymentDetails(7));
    }

    @Test
    void queryCloseAndConfirmMustCompleteBeforeLocalAttemptIsClosed() {
        when(transactionDao.findActiveByOrder(7)).thenReturn(Optional.of(payment("PENDING", null)));
        when(gateway.query("ALI123")).thenReturn(new PaymentGateway.QueryResult(false, false, null),
                new PaymentGateway.QueryResult(false, true, null));

        service.closePendingPayment(7);

        var sequence = inOrder(gateway, transactionDao);
        sequence.verify(transactionDao).findActiveByOrder(7);
        sequence.verify(gateway).query("ALI123");
        sequence.verify(gateway).close("ALI123");
        sequence.verify(gateway).query("ALI123");
        sequence.verify(transactionDao).markClosed(9);
    }

    @Test
    void failedProviderCloseDoesNotReleaseLocalAttempt() {
        when(transactionDao.findActiveByOrder(7)).thenReturn(Optional.of(payment("PENDING", null)));
        when(gateway.query("ALI123")).thenReturn(new PaymentGateway.QueryResult(false, false, null));
        doThrow(new IllegalStateException("provider offline")).when(gateway).close("ALI123");

        assertThrows(IllegalStateException.class, () -> service.closePendingPayment(7));

        verify(transactionDao, never()).markClosed(anyLong());
    }

    @Test
    void queryFindingPaymentSettlesItInsteadOfClosingTheCharge() {
        PaymentGateway.VerifiedNotice paid = new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1300, "CNY", true);
        when(transactionDao.findActiveByOrder(7)).thenReturn(Optional.of(payment("PENDING", null)));
        when(gateway.query("ALI123")).thenReturn(new PaymentGateway.QueryResult(true, false, paid));
        when(transactionDao.findByOutTradeNo("ALI123")).thenReturn(Optional.of(payment("PENDING", null)));
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(pendingOrder()));
        when(orderDao.markPaid(eq(7L), anyString())).thenReturn(true);
        when(transactionDao.markSuccess(eq(9L), eq("provider-1"), anyString())).thenReturn(true);

        service.closePendingPayment(7);

        verify(orderDao).markPaid(eq(7L), anyString());
        verify(gateway, never()).close(anyString());
        verify(transactionDao, never()).markClosed(anyLong());
    }

    @Test
    void activeRefreshSettlesTheVerifiedProviderPaymentWithoutClosingIt() {
        PaymentGateway.VerifiedNotice paid = new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1300, "CNY", true);
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(pendingOrder()));
        when(transactionDao.findActiveByOrder(7)).thenReturn(Optional.of(payment("PENDING", null)));
        when(gateway.query("ALI123")).thenReturn(new PaymentGateway.QueryResult(true, false, paid));
        when(transactionDao.findByOutTradeNo("ALI123")).thenReturn(Optional.of(payment("PENDING", null)));
        when(orderDao.markPaid(eq(7L), anyString())).thenReturn(true);
        when(transactionDao.markSuccess(eq(9L), eq("provider-1"), anyString())).thenReturn(true);

        service.refreshPayment(7);

        verify(orderDao).markPaid(eq(7L), anyString());
        verify(paymentRecordDao).insert(eq(7L), eq(2L), eq(13.0), eq("PAY"), eq("ALIPAY"), eq("SUCCESS"), anyString());
        verify(gateway, never()).close(anyString());
        verify(transactionDao, never()).markClosed(anyLong());
    }

    @Test
    void activeRefreshLeavesUnpaidTradePending() {
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(pendingOrder()));
        when(transactionDao.findActiveByOrder(7)).thenReturn(Optional.of(payment("PENDING", null)));
        for (boolean closedOrNotCreated : new boolean[]{false, true}) {
            when(gateway.query("ALI123")).thenReturn(new PaymentGateway.QueryResult(false, closedOrNotCreated, null));
            service.refreshPayment(7);
        }

        verify(orderDao, never()).markPaid(anyLong(), anyString());
        verify(transactionDao, never()).markSuccess(anyLong(), anyString(), anyString());
        verify(transactionDao, never()).markClosed(anyLong());
    }

    @Test
    void activeRefreshRejectsProviderAmountMismatch() {
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(pendingOrder()));
        when(transactionDao.findActiveByOrder(7)).thenReturn(Optional.of(payment("PENDING", null)));
        when(gateway.query("ALI123")).thenReturn(new PaymentGateway.QueryResult(true, false,
                new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1299, "CNY", true)));
        when(transactionDao.findByOutTradeNo("ALI123")).thenReturn(Optional.of(payment("PENDING", null)));

        assertThrows(SecurityException.class, () -> service.refreshPayment(7));

        verify(orderDao, never()).markPaid(anyLong(), anyString());
        verify(transactionDao, never()).markSuccess(anyLong(), anyString(), anyString());
    }

    @Test
    void originalProviderRefundUsesStableId() {
        when(transactionDao.findSuccessfulByOrder(7)).thenReturn(Optional.of(payment("SUCCESS", "provider-1")));

        assertEquals("ALIPAY", service.refundOriginalPayment(order(1)));

        verify(gateway).refund("ALI123", "RALI123", new BigDecimal("13.00"), new BigDecimal("13.00"));
        verify(transactionDao).markRefunded(9);
    }

    @Test
    void partialAfterSalesUsesStablePerRecordRefundNumberAndOriginalTotal() {
        when(transactionDao.findSuccessfulByOrder(7)).thenReturn(Optional.of(payment("SUCCESS", "provider-1")));
        service.refundOriginalPayment(order(6), new BigDecimal("2.25"), 81, false);
        service.refundOriginalPayment(order(6), new BigDecimal("2.25"), 81, false);
        service.refundOriginalPayment(order(6), new BigDecimal("10.75"), 82, true);
        verify(gateway, org.mockito.Mockito.times(2)).refund("ALI123", "AS9R81", new BigDecimal("2.25"), new BigDecimal("13.00"));
        verify(gateway).refund("ALI123", "AS9R82", new BigDecimal("10.75"), new BigDecimal("13.00"));
        verify(transactionDao).markRefunded(9);
    }

    @Test
    void providerRefundFailureLeavesThePaymentUnrefunded() {
        when(transactionDao.findSuccessfulByOrder(7)).thenReturn(Optional.of(payment("SUCCESS", "provider-1")));
        doThrow(new IllegalStateException("pending provider refund")).when(gateway)
                .refund("ALI123", "RALI123", new BigDecimal("13.00"), new BigDecimal("13.00"));

        assertThrows(IllegalStateException.class, () -> service.refundOriginalPayment(order(1)));

        verify(transactionDao, never()).markRefunded(anyLong());
    }

    @Test
    void concurrentDuplicateReadAfterOrderLockDoesNotRefundAnAlreadySettledCharge() {
        when(gateway.verifyNotification("raw", Map.of())).thenReturn(
                new PaymentGateway.VerifiedNotice("ALI123", "provider-1", 1300, "CNY", true));
        when(transactionDao.findByOutTradeNo("ALI123"))
                .thenReturn(Optional.of(payment("PENDING", null)));
        when(transactionDao.findByOutTradeNoForUpdate("ALI123"))
                .thenReturn(Optional.of(payment("SUCCESS", "provider-1")));
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(order(1)));

        assertEquals(ExternalPaymentService.NotificationResult.DUPLICATE,
                service.acceptNotification(PaymentChannels.ALIPAY, "raw", Map.of()));

        verify(gateway, never()).refund(anyString(), anyString(), any());
        verify(orderDao, never()).markPaid(anyLong(), anyString());
    }

    @Test
    void completeWechatCredentialsCannotEnablePaymentsInSandboxOrProductionMode() {
        var settings = properties.getWechat();
        settings.setMchId("configured-mch");
        settings.setAppId("configured-app");
        settings.setPrivateKeyPath("configured-key.pem");
        settings.setMerchantSerialNumber("configured-serial");
        settings.setApiV3Key("configured-api-v3-key");
        settings.setNotifyUrl("https://callback.example/api/payment/wechat/notify");
        for (boolean sandbox : new boolean[]{true, false}) {
            properties.setSandbox(sandbox);

            BizException failure = assertThrows(BizException.class,
                    () -> service.startPayment(PaymentChannels.WECHAT, pendingOrder()));

            assertEquals(503, failure.getCode());
            assertTrue(failure.getMessage().contains("异步退款"));
        }
        verify(orderDao, never()).findByIdForUpdate(anyLong());
        verify(transactionDao, never()).insertPending(anyLong(), anyLong(), anyString(), any(), anyString(), anyString());
        verify(gateway, never()).createQrPayment(anyString(), anyString(), any(), any());
    }

    @Test
    void wechatNotificationsAndRefundsAreRejectedBeforeCallingAnyProvider() {
        properties.setSandbox(false);
        PaymentTransaction previousWechatPayment = new PaymentTransaction(9, 7, 2, PaymentChannels.WECHAT,
                new BigDecimal("13.00"), "WX-disabled", "provider-1", "SUCCESS", "", now(), null);
        when(transactionDao.findSuccessfulByOrder(7)).thenReturn(Optional.of(previousWechatPayment));

        assertThrows(BizException.class,
                () -> service.acceptNotification(PaymentChannels.WECHAT, "raw", Map.of()));
        assertThrows(BizException.class, () -> service.refundOriginalPayment(order(1)));

        verify(gateway, never()).verifyNotification(anyString(), any());
        verify(gateway, never()).refund(anyString(), anyString(), any());
        verify(transactionDao, never()).markRefunded(anyLong());
    }

    private static PaymentTransaction payment(String status, String providerId) {
        return new PaymentTransaction(9, 7, 2, PaymentChannels.ALIPAY, new BigDecimal("13.00"),
                "ALI123", providerId, status, "https://qr.alipay.test/pay", "2026-10-14 10:00:00", null);
    }

    private void productionMode() {
        properties.setSandbox(false);
        properties.getAlipay().setGatewayUrl("https://openapi.alipay.com/gateway.do");
    }

    private static PaymentTransaction appPayment(String status) {
        return new PaymentTransaction(9, 7, 2, "ALIPAY", new BigDecimal("13.00"), "ALI123", null,
                status, "app_id=old-order", now(), null, "APP");
    }

    private AtomicReference<PaymentTransaction> paymentFixture(PaymentTransaction initial) {
        var active = new AtomicReference<>(initial);
        when(orderDao.findByIdForUpdate(7)).thenReturn(Optional.of(pendingOrder()));
        when(transactionDao.findActiveByOrder(7)).thenAnswer(invocation -> Optional.ofNullable(active.get()));
        when(transactionDao.insertPending(anyLong(), anyLong(), anyString(), any(), anyString(), anyString(), anyString()))
                .thenAnswer(invocation -> {
                    active.set(new PaymentTransaction(10, 7, 2, "ALIPAY", new BigDecimal("13.00"),
                            invocation.getArgument(4), null, "PENDING", "", now(), null, invocation.getArgument(6)));
                    return 10L;
                });
        org.mockito.Mockito.doAnswer(invocation -> { active.set(null); return null; }).when(transactionDao).markClosed(anyLong());
        when(transactionDao.setPaymentUrl(anyLong(), anyString())).thenAnswer(invocation -> {
            var previous = active.get();
            active.set(new PaymentTransaction(previous.id(), 7, 2, "ALIPAY", previous.amount(), previous.outTradeNo(),
                    null, "PENDING", invocation.getArgument(1), now(), null, previous.paymentMode()));
            return true;
        });
        return active;
    }

    private static Order pendingOrder() {
        return order(0);
    }

    private static Order order(int status) {
        return new Order(7, "NO7", 2, 3, "店铺", status, "[]", "{}", 10, 3, 0, 13,
                "", 0, 0, LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")),
                "", "", "", "", "", 0);
    }

    private static String now() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }
}
