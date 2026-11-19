package com.example.takeout.service.thirdparty;

import com.example.takeout.common.BizException;
import com.example.takeout.common.BusinessIdGenerator;
import com.example.takeout.config.PaymentProperties;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.PaymentTransactionDao;
import com.example.takeout.model.Order;
import com.example.takeout.model.PaymentTransaction;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.example.takeout.service.TransactionRetries;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class ExternalPaymentService {

    private static final DateTimeFormatter TIME_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final PaymentProperties properties;
    private final Map<String, PaymentGateway> gateways;
    private final PaymentTransactionDao transactionDao;
    private final OrderDao orderDao;
    private final PaymentRecordDao paymentRecordDao;
    private final DomainEventPublisher eventPublisher;
    private TransactionTemplate transactions;
    private com.example.takeout.service.ExternalRefundAttemptService refundAttempts;

    @Autowired
    public void configureRefundAttempts(com.example.takeout.service.ExternalRefundAttemptService refundAttempts) {
        this.refundAttempts = refundAttempts;
    }
    private com.example.takeout.service.PromotionService promotions;
    @Autowired
    private com.example.takeout.dao.StoreDao stores;

    @Autowired
    void configureBusinessRules(com.example.takeout.service.PromotionService promotions) {
        this.promotions = promotions;
    }

    @Autowired
    void configureTransactions(TransactionTemplate transactions) {
        this.transactions = transactions;
    }

    @Value("${takeout.order.pay-timeout-minutes:15}")
    private int payTimeoutMinutes = 15;

    public ExternalPaymentService(PaymentProperties properties, List<PaymentGateway> gateways,
                                  PaymentTransactionDao transactionDao, OrderDao orderDao,
                                  PaymentRecordDao paymentRecordDao, DomainEventPublisher eventPublisher) {
        this.properties = properties;
        Map<String, PaymentGateway> index = new HashMap<>();
        for (PaymentGateway gateway : gateways) index.put(gateway.channel(), gateway);
        this.gateways = Map.copyOf(index);
        this.transactionDao = transactionDao;
        this.orderDao = orderDao;
        this.paymentRecordDao = paymentRecordDao;
        this.eventPublisher = eventPublisher;
    }

    public PaymentLaunch startPayment(String channel, Order order) {
        return startPayment(channel, order, "QR");
    }

    public PaymentLaunch startPayment(String channel, Order order, String mode) {
        requireOutsideTransaction();
        mode = normalizeMode(mode);
        if (!providerPaymentsEnabled()) {
            throw new BizException(503, "第三方支付尚未启用，请联系管理员");
        }
        PaymentGateway gateway = requireGateway(channel);
        String paymentMode = mode;
        PaymentTransaction previous = transactionDao.findActiveByOrder(order.id()).orElse(null);
        if (previous != null && channel.equals(previous.channel()) && !paymentMode.equals(previous.paymentMode())) {
            closePendingPayment(order.id());
        }
        PaymentTransaction active = TransactionRetries.execute(transactions, status -> preparePayment(channel, paymentMode, order));
        if (!"PENDING".equals(active.status()) || !blank(active.paymentUrl())) return launch(active);
        return createPrepay(gateway, active, order.orderNo());
    }

    public static String normalizeMode(String mode) {
        String normalized = mode == null ? "QR" : mode.trim().toUpperCase(java.util.Locale.ROOT);
        if (!"APP".equals(normalized) && !"QR".equals(normalized)) throw new BizException("不支持的支付场景");
        return normalized;
    }

    public PaymentLaunch paymentDetails(long orderId) {
        return transactionDao.findLatestByOrder(orderId)
                .filter(payment -> "PENDING".equals(payment.status()) || "SUCCESS".equals(payment.status())
                        || "REFUNDED".equals(payment.status()))
                .map(this::launch).orElse(null);
    }

    /** SDK 校验查单响应签名；通知未及时到达时复用同一事务和幂等校验确认支付。 */
    public void refreshPayment(long orderId) {
        requireOutsideTransaction();
        Order order = orderDao.findById(orderId).orElseThrow(() -> new BizException("订单不存在"));
        if (order.status() != 0) return;
        PaymentTransaction payment = transactionDao.findActiveByOrder(orderId).orElse(null);
        if (payment == null) return;
        if (!providerPaymentsEnabled()) throw new BizException(503, "第三方支付尚未启用，请联系管理员");
        PaymentGateway.QueryResult result = requireGateway(payment.channel()).query(payment.outTradeNo());
        if (result.paid()) settleVerifiedNotice(payment.channel(), result.notice());
    }

    private PaymentTransaction preparePayment(String channel, String mode, Order original) {
        Order order = orderDao.findByIdForUpdate(original.id()).orElseThrow(() -> new BizException("订单不存在"));
        if (order.userId() != original.userId()) throw new BizException(403, "无权操作该订单");
        if (order.status() == 1) {
            PaymentTransaction successful = transactionDao.findSuccessfulByOrder(order.id()).orElse(null);
            if (successful != null && "SUCCESS".equals(successful.status())) return successful;
        }
        if (order.status() != 0 || isExpired(order.createTime())) throw new BizException("订单已无法支付");
        if (stores != null) stores.lockForOrderAdmission(order.storeId(), false);
        PaymentTransaction active = transactionDao.findActiveByOrder(order.id()).orElse(null);
        if (active != null) {
            if (!channel.equals(active.channel())) {
                throw new BizException(409, "该订单已有其他支付渠道正在处理");
            }
            if (mode.equals(active.paymentMode())) return active;
            throw new BizException(409, "支付入口正在切换，请刷新后重试");
        }

        BigDecimal amount = BigDecimal.valueOf(order.payAmount()).setScale(2);
        String outTradeNo = newOutTradeNo(channel);
        long id;
        try {
            id = transactionDao.insertPending(order.id(), order.userId(), channel, amount, outTradeNo,
                    LocalDateTime.now().format(TIME_FORMAT), mode);
        } catch (DuplicateKeyException concurrentStart) {
            PaymentTransaction concurrent = transactionDao.findActiveByOrder(order.id()).orElse(null);
            if (concurrent == null || !channel.equals(concurrent.channel()) || !mode.equals(concurrent.paymentMode())) {
                throw new BizException(409, "支付请求正在处理，请刷新订单后重试");
            }
            return concurrent;
        }

        return new PaymentTransaction(id, order.id(), order.userId(), channel, amount,
                outTradeNo, null, "PENDING", "", LocalDateTime.now().format(TIME_FORMAT), null, mode);
    }

    public NotificationResult acceptNotification(String channel, String rawBody, Map<String, String> metadata) {
        requireOutsideTransaction();
        if (!providerPaymentsEnabled()) {
            throw new SecurityException("Payment notifications are disabled");
        }
        PaymentGateway gateway = requireGateway(channel);
        PaymentGateway.VerifiedNotice notice = gateway.verifyNotification(rawBody, metadata);
        return settleVerifiedNotice(channel, notice);
    }

    private NotificationResult settleVerifiedNotice(String channel, PaymentGateway.VerifiedNotice notice) {
        NotificationResult result = TransactionRetries.execute(transactions, status -> applyVerifiedNotice(channel, notice));
        if (result != NotificationResult.REFUND_PENDING) return result;
        PaymentTransaction payment = transactionDao.findByOutTradeNo(notice.outTradeNo()).orElseThrow();
        executeRefund(refundAttempts.find(refundNo(payment)).orElseThrow());
        return TransactionRetries.execute(transactions, status -> applyVerifiedNotice(channel, notice));
    }

    private NotificationResult applyVerifiedNotice(String channel, PaymentGateway.VerifiedNotice notice) {
        if (notice == null || !notice.paid() || notice.outTradeNo() == null || notice.outTradeNo().isBlank()
                || notice.providerTransactionId() == null || notice.providerTransactionId().isBlank()
                || notice.amountFen() <= 0 || !"CNY".equals(notice.currency())) {
            throw new SecurityException("Payment notification is incomplete or not successful");
        }

        PaymentTransaction payment = transactionDao.findByOutTradeNo(notice.outTradeNo())
                .orElseThrow(() -> new SecurityException("Unknown payment order"));
        if (!channel.equals(payment.channel()) || notice.amountFen() != amountFen(payment.amount())) {
            throw new SecurityException("Payment channel or amount mismatch");
        }
        if ("SUCCESS".equals(payment.status()) || "REFUNDED".equals(payment.status()) || "LATE_REFUNDED".equals(payment.status())) {
            if (notice.providerTransactionId().equals(payment.providerTransactionId())) {
                return NotificationResult.DUPLICATE;
            }
            throw new SecurityException("Payment transaction does not match the completed attempt");
        }
        if (!"PENDING".equals(payment.status()) && !"CLOSED".equals(payment.status())) {
            throw new SecurityException("Payment attempt is not pending");
        }

        Order order = orderDao.findByIdForUpdate(payment.orderId())
                .orElseThrow(() -> new SecurityException("Order does not exist"));
        // A locking read observes a preceding callback's commit under MySQL REPEATABLE READ.
        payment = transactionDao.findByOutTradeNoForUpdate(notice.outTradeNo())
                .orElseThrow(() -> new SecurityException("Unknown payment order"));
        if ("SUCCESS".equals(payment.status()) || "REFUNDED".equals(payment.status()) || "LATE_REFUNDED".equals(payment.status())) {
            if (notice.providerTransactionId().equals(payment.providerTransactionId())) return NotificationResult.DUPLICATE;
            throw new SecurityException("Payment transaction mismatch");
        }
        if (order.userId() != payment.userId()
                || notice.amountFen() != amountFen(BigDecimal.valueOf(order.payAmount()))) {
            throw new SecurityException("Order state or amount mismatch");
        }
        if ("CLOSED".equals(payment.status()) || order.status() != 0 || isExpired(order.createTime())) {
            // A late success can race a timeout/other payment. Refund the verified charge with a stable idempotency key.
            if (!prepareRefund("LATE", payment, 0, refundNo(payment), payment.amount(), notice.providerTransactionId(), null)) {
                return NotificationResult.REFUND_PENDING;
            }
            refundAttempts.completeInTransaction(refundNo(payment));
            transactionDao.markLateRefunded(payment.id(), notice.providerTransactionId(), now());
            // The verified charge and its compensating refund are both financial facts.
            paymentRecordDao.insert(order.id(), order.userId(), order.payAmount(), "PAY", channel, "SUCCESS", now());
            paymentRecordDao.insert(order.id(), order.userId(), order.payAmount(), "REFUND", channel, "SUCCESS", now());
            return NotificationResult.REFUNDED;
        }

        String now = now();
        if (!orderDao.markPaid(order.id(), now)) {
            throw new SecurityException("Order state changed before payment confirmation");
        }
        if (!transactionDao.markSuccess(payment.id(), notice.providerTransactionId(), now)) {
            throw new SecurityException("Payment attempt was already handled");
        }
        paymentRecordDao.insert(order.id(), order.userId(), order.payAmount(), "PAY", channel, "SUCCESS", now);
        if (promotions != null) promotions.paid(order.id());
        eventPublisher.publish(DomainEventPublisher.ORDER_PAID, order.id(),
                Map.of("userId", order.userId(), "payAmount", order.payAmount()));
        return NotificationResult.PAID;
    }

    /** Close before cancellation; a success discovered by the query is settled and caller reloads the order. */
    public void closePendingPayment(long orderId) {
        requireOutsideTransaction();
        PaymentTransaction payment = transactionDao.findActiveByOrder(orderId).orElse(null);
        if (payment == null) return;
        PaymentGateway gateway = requireGateway(payment.channel());
        PaymentGateway.QueryResult result = gateway.query(payment.outTradeNo());
        if (result.paid()) {
            PaymentGateway.VerifiedNotice paid = result.notice();
            settleVerifiedNotice(payment.channel(), paid);
            return;
        }
        if (!result.closed()) {
            gateway.close(payment.outTradeNo());
            result = gateway.query(payment.outTradeNo());
            if (result.paid()) {
                PaymentGateway.VerifiedNotice paid = result.notice();
                settleVerifiedNotice(payment.channel(), paid);
                return;
            }
            if (!result.closed()) throw new BizException(503, "支付渠道关单尚未确认，请稍后重试");
        }
        TransactionRetries.executeWithoutResult(transactions, status -> {
            orderDao.findByIdForUpdate(orderId).orElseThrow(() -> new BizException("订单不存在"));
            transactionDao.markClosed(payment.id());
        });
    }

    /** Direct compatibility callers still enter the durable cancellation refund protocol. */
    public String refundOriginalPayment(Order order) {
        return refundOriginalPayment(order, new com.example.takeout.service.ExternalRefundAttemptService.Cancellation(
                "ADMIN", "PLATFORM_CANCELLED", "平台取消订单", 0, "", 0, 0));
    }

    public String refundOriginalPayment(Order order, com.example.takeout.service.ExternalRefundAttemptService.Cancellation cancellation) {
        PaymentTransaction payment = transactionDao.findSuccessfulByOrder(order.id()).orElse(null);
        if (payment == null) return PaymentChannels.BALANCE;
        if ("REFUNDED".equals(payment.status())) return payment.channel();
        requireConfirmedRefund(refundNo(payment));
        transactionDao.markRefunded(payment.id());
        return payment.channel();
    }

    public String refundOriginalPayment(Order order, BigDecimal amount, long refundId, boolean full) {
        PaymentTransaction payment = transactionDao.findSuccessfulByOrder(order.id()).orElse(null);
        if (payment == null) return PaymentChannels.BALANCE;
        if ("REFUNDED".equals(payment.status())) throw new BizException("原支付已全额退款");
        if (amount.signum() <= 0 || amount.compareTo(payment.amount()) > 0) throw new BizException("退款金额无效");
        requireConfirmedRefund("AS" + payment.id() + "R" + refundId);
        if (full) transactionDao.markRefunded(payment.id());
        return payment.channel();
    }

    public boolean prepareCancellationRefund(Order order, com.example.takeout.service.ExternalRefundAttemptService.Cancellation cancellation) {
        PaymentTransaction payment = transactionDao.findSuccessfulByOrder(order.id()).orElse(null);
        return payment == null || "REFUNDED".equals(payment.status()) || prepareRefund("CANCEL", payment, 0,
                refundNo(payment), payment.amount(), payment.providerTransactionId(), cancellation);
    }

    public boolean prepareAfterSalesRefund(Order order, BigDecimal amount, long refundId) {
        PaymentTransaction payment = transactionDao.findSuccessfulByOrder(order.id()).orElse(null);
        if (payment == null) return true;
        if ("REFUNDED".equals(payment.status()) || amount.signum() <= 0 || amount.compareTo(payment.amount()) > 0)
            throw new BizException("原支付已退款或退款金额无效");
        return prepareRefund("AFTER_SALES", payment, refundId, "AS" + payment.id() + "R" + refundId,
                amount, payment.providerTransactionId(), null);
    }

    private boolean prepareRefund(String kind, PaymentTransaction payment, long refundId, String number, BigDecimal amount,
                              String providerId, com.example.takeout.service.ExternalRefundAttemptService.Cancellation cancellation) {
        requireGateway(payment.channel());
        var attempt = refundAttempts.prepare(kind, payment, refundId, number, amount, providerId, cancellation);
        return !"REQUESTED".equals(attempt.status());
    }

    public void executeRefund(com.example.takeout.service.ExternalRefundAttemptService.Attempt attempt) {
        requireOutsideTransaction();
        var current = refundAttempts.find(attempt.refundNo()).orElseThrow();
        if (!"REQUESTED".equals(current.status())) return;
        requireGateway(current.channel()).refund(current.outTradeNo(), current.refundNo(), current.amount(), current.originalAmount());
        refundAttempts.confirmed(current.refundNo());
    }

    private void requireConfirmedRefund(String number) {
        var attempt = refundAttempts.find(number).orElseThrow(() -> new BizException(409, "退款尚未登记"));
        if ("REQUESTED".equals(attempt.status())) throw new BizException(409, "退款渠道正在处理中，请稍后重试");
        refundAttempts.completeInTransaction(number);
    }

    /** Stored provider identity and amount were verified before the independent LATE intent was written. */
    public void recoverLateRefund(com.example.takeout.service.ExternalRefundAttemptService.Attempt attempt) {
        if (!"LATE".equals(attempt.kind())) throw new IllegalArgumentException("Not a late payment refund");
        executeRefund(attempt);
        TransactionRetries.executeWithoutResult(transactions, status -> {
            applyVerifiedNotice(attempt.channel(), new PaymentGateway.VerifiedNotice(attempt.outTradeNo(),
                    attempt.providerTransactionId(), amountFen(attempt.originalAmount()), "CNY", true));
            refundAttempts.completeInTransaction(attempt.refundNo());
        });
    }

    public boolean hasPendingPayment(long orderId) {
        return transactionDao.findActiveByOrder(orderId).isPresent();
    }

    private PaymentLaunch createPrepay(PaymentGateway gateway, PaymentTransaction payment, String orderNo) {
        try {
            requireOutsideTransaction();
            Order snapshot = orderDao.findById(payment.orderId()).orElseThrow(() -> new BizException("订单不存在"));
            if (snapshot.status() != 0 || isExpired(snapshot.createTime())) throw new BizException("订单已无法支付");
            LocalDateTime expiresAt = LocalDateTime.parse(snapshot.createTime(), TIME_FORMAT)
                    .plusMinutes(Math.max(1, payTimeoutMinutes));
            String url = "APP".equals(payment.paymentMode())
                    ? gateway.createAppPayment(payment.outTradeNo(), "外卖订单 " + orderNo, payment.amount(), expiresAt)
                    : gateway.createQrPayment(payment.outTradeNo(), "外卖订单 " + orderNo, payment.amount(), expiresAt);
            return TransactionRetries.execute(transactions, status -> {
                Order locked = orderDao.findByIdForUpdate(payment.orderId())
                        .orElseThrow(() -> new BizException("订单不存在"));
                if (locked.status() != 0 || isExpired(locked.createTime())) throw new BizException("订单已无法支付");
                PaymentTransaction current = transactionDao.findActiveByOrder(payment.orderId()).orElse(null);
                if (current == null || current.id() != payment.id()) {
                    throw new BizException(409, "支付请求已更新，请刷新后重试");
                }
                if (!blank(current.paymentUrl())) return launch(current);
                transactionDao.setPaymentUrl(payment.id(), url);
                return launch(new PaymentTransaction(payment.id(), payment.orderId(), payment.userId(), payment.channel(),
                        payment.amount(), payment.outTradeNo(), null, "PENDING", url, payment.createTime(), null,
                        payment.paymentMode()));
            });
        } catch (BizException e) {
            throw e;
        } catch (RuntimeException e) {
            // Do not discard an uncertain network attempt: retrying always reuses its provider order number.
            throw new BizException(503, "支付渠道暂不可用，请重试或取消订单");
        }
    }

    private PaymentGateway requireGateway(String channel) {
        if (PaymentChannels.WECHAT.equals(channel)) {
            // No configuration override: enabling credentials alone cannot expose an unsafe asynchronous refund flow.
            throw new BizException(503, "微信支付尚未开放：需先完成异步退款持久化与状态收口");
        }
        if (PaymentChannels.ALIPAY.equals(channel)) {
            PaymentProperties.Alipay settings = properties.getAlipay();
            String expectedGateway = properties.isSandbox()
                    ? "https://openapi-sandbox.dl.alipaydev.com/gateway.do" : "https://openapi.alipay.com/gateway.do";
            if (!expectedGateway.equals(settings.getGatewayUrl()) || blank(settings.getAppPrivateKey())
                    || blank(settings.getPublicKey()) || !https(settings.getNotifyUrl())) {
                throw new BizException(503, "支付宝支付凭据或HTTPS回调地址未配置");
            }
        }
        PaymentGateway gateway = gateways.get(channel);
        if (gateway == null) throw new BizException(503, "支付渠道暂不可用");
        return gateway;
    }

    private boolean providerPaymentsEnabled() {
        return !properties.isMockEnabled() && (properties.isRealEnabled() || properties.isSandbox());
    }

    private PaymentLaunch launch(PaymentTransaction payment) {
        String payload = "PENDING".equals(payment.status()) && payment.paymentUrl() != null
                ? payment.paymentUrl() : "";
        boolean app = "APP".equals(payment.paymentMode());
        return new PaymentLaunch(payment.channel(), payment.outTradeNo(),
                app ? "" : payload, payment.status(), app ? payload : "", payment.paymentMode(), properties.isSandbox());
    }

    private boolean isExpired(String createdAt) {
        try {
            return LocalDateTime.now().isAfter(LocalDateTime.parse(createdAt, TIME_FORMAT)
                    .plusMinutes(Math.max(1, payTimeoutMinutes)));
        } catch (RuntimeException e) {
            throw new SecurityException("Order creation time is invalid");
        }
    }

    private static long amountFen(BigDecimal amount) {
        try {
            return amount.setScale(2).movePointRight(2).longValueExact();
        } catch (ArithmeticException e) {
            throw new SecurityException("Order amount is invalid");
        }
    }

    private static String newOutTradeNo(String channel) {
        char prefix = PaymentChannels.WECHAT.equals(channel) ? 'W' : 'A';
        return prefix + BusinessIdGenerator.nextId();
    }

    private static String refundNo(PaymentTransaction payment) {
        return "R" + payment.outTradeNo();
    }

    private static String now() {
        return LocalDateTime.now().format(TIME_FORMAT);
    }

    private static void requireOutsideTransaction() {
        if (org.springframework.transaction.support.TransactionSynchronizationManager.isActualTransactionActive())
            throw new IllegalStateException("Payment channel I/O must run outside a database transaction");
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }

    private static boolean https(String value) {
        try {
            java.net.URI uri = java.net.URI.create(value);
            return "https".equals(uri.getScheme()) && uri.getHost() != null && uri.getUserInfo() == null;
        } catch (RuntimeException e) {
            return false;
        }
    }

    public record PaymentLaunch(String channel, String outTradeNo, String paymentUrl, String status,
                                String appOrderInfo, String paymentMode, boolean paymentSandbox) {
        public PaymentLaunch(String channel, String outTradeNo, String paymentUrl, String status) {
            this(channel, outTradeNo, paymentUrl, status, "", "QR", false);
        }
    }

    public enum NotificationResult { PAID, DUPLICATE, REFUNDED, REFUND_PENDING }
}
