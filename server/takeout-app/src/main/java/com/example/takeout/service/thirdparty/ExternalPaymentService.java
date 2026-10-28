package com.example.takeout.service.thirdparty;

import com.example.takeout.common.BizException;
import com.example.takeout.config.PaymentProperties;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.PaymentRecordDao;
import com.example.takeout.dao.PaymentTransactionDao;
import com.example.takeout.model.Order;
import com.example.takeout.model.PaymentTransaction;
import com.example.takeout.service.mq.DomainEventPublisher;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class ExternalPaymentService {

    private static final DateTimeFormatter TIME_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final char[] TRADE_CHARS = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".toCharArray();

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
    private com.example.takeout.service.HotDataCacheService cache;

    @Autowired
    void configureBusinessRules(com.example.takeout.service.PromotionService promotions,
                                com.example.takeout.service.HotDataCacheService cache) {
        this.promotions = promotions;
        this.cache = cache;
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
        mode = normalizeMode(mode);
        if (!providerPaymentsEnabled()) {
            throw new BizException(503, "第三方支付尚未启用，请联系管理员");
        }
        PaymentGateway gateway = requireGateway(channel);
        String paymentMode = mode;
        PaymentTransaction active = transactions.execute(status -> preparePayment(channel, paymentMode, order));
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
        transactions.executeWithoutResult(status -> {
            Order order = orderDao.findByIdForUpdate(orderId).orElseThrow(() -> new BizException("订单不存在"));
            if (order.status() != 0) return;
            PaymentTransaction payment = transactionDao.findActiveByOrder(orderId).orElse(null);
            if (payment == null) return;
            if (!providerPaymentsEnabled()) throw new BizException(503, "第三方支付尚未启用，请联系管理员");
            PaymentGateway.QueryResult result = requireGateway(payment.channel()).query(payment.outTradeNo());
            if (result.paid()) applyVerifiedNotice(payment.channel(), result.notice());
            // 未扫描的支付宝二维码可能尚无交易；只由取消流程关闭本地预支付，避免刷新清掉二维码。
        });
    }

    private PaymentTransaction preparePayment(String channel, String mode, Order original) {
        Order order = orderDao.findByIdForUpdate(original.id()).orElseThrow(() -> new BizException("订单不存在"));
        if (order.status() != 0 || isExpired(order.createTime())) throw new BizException("订单已无法支付");
        PaymentTransaction active = transactionDao.findActiveByOrder(order.id()).orElse(null);
        if (active != null) {
            if (!channel.equals(active.channel())) {
                throw new BizException(409, "该订单已有其他支付渠道正在处理");
            }
            if (mode.equals(active.paymentMode())) return active;
            // Changing SDK/QR entry points must first close the previous provider trade under the order row lock.
            // If the old SDK payload is paid late, the existing CLOSED callback path refunds that charge.
            try {
                closePendingPayment(order.id());
            } catch (IllegalStateException providerUnavailable) {
                throw new BizException(503, "支付状态暂无法确认，请稍后重试扫码支付");
            }
            Order latest = orderDao.findByIdForUpdate(order.id()).orElseThrow(() -> new BizException("订单不存在"));
            if (latest.status() != 0) {
                return transactionDao.findSuccessfulByOrder(order.id())
                        .orElseThrow(() -> new BizException(409, "订单状态已变化，请刷新后重试"));
            }
        }

        BigDecimal amount = BigDecimal.valueOf(order.payAmount()).setScale(2);
        String outTradeNo = newOutTradeNo(channel, order.id());
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
        if (!providerPaymentsEnabled()) {
            throw new SecurityException("Payment notifications are disabled");
        }
        PaymentGateway gateway = requireGateway(channel);
        PaymentGateway.VerifiedNotice notice = gateway.verifyNotification(rawBody, metadata);
        return transactions.execute(status -> applyVerifiedNotice(channel, notice));
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
            submitRefund("LATE", payment, 0, refundNo(payment), payment.amount(), notice.providerTransactionId(), null);
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
        if (cache != null) DomainEventPublisher.afterCommit(() -> {
            for (String pattern : com.example.takeout.service.HotDataCacheService.Keys.STOCK_DEPENDENT_PATTERNS) cache.evictByPattern(pattern);
        });
        eventPublisher.publish(DomainEventPublisher.ORDER_PAID, order.id(),
                Map.of("userId", order.userId(), "payAmount", order.payAmount()));
        return NotificationResult.PAID;
    }

    /** Close before cancellation; a success discovered by the query is settled and caller reloads the order. */
    public void closePendingPayment(long orderId) {
        PaymentTransaction payment = transactionDao.findActiveByOrder(orderId).orElse(null);
        if (payment == null) return;
        PaymentGateway gateway = requireGateway(payment.channel());
        PaymentGateway.QueryResult result = gateway.query(payment.outTradeNo());
        if (result.paid()) {
            PaymentGateway.VerifiedNotice paid = result.notice();
            transactions.execute(status -> applyVerifiedNotice(payment.channel(), paid));
            return;
        }
        if (!result.closed()) {
            gateway.close(payment.outTradeNo());
            result = gateway.query(payment.outTradeNo());
            if (result.paid()) {
                PaymentGateway.VerifiedNotice paid = result.notice();
                transactions.execute(status -> applyVerifiedNotice(payment.channel(), paid));
                return;
            }
            if (!result.closed()) throw new BizException(503, "支付渠道关单尚未确认，请稍后重试");
        }
        transactionDao.markClosed(payment.id());
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
        submitRefund("CANCEL", payment, 0, refundNo(payment), payment.amount(), payment.providerTransactionId(), cancellation);
        transactionDao.markRefunded(payment.id());
        return payment.channel();
    }

    public String refundOriginalPayment(Order order, BigDecimal amount, long refundId, boolean full) {
        PaymentTransaction payment = transactionDao.findSuccessfulByOrder(order.id()).orElse(null);
        if (payment == null) return PaymentChannels.BALANCE;
        if ("REFUNDED".equals(payment.status())) throw new BizException("原支付已全额退款");
        if (amount.signum() <= 0 || amount.compareTo(payment.amount()) > 0) throw new BizException("退款金额无效");
        submitRefund("AFTER_SALES", payment, refundId, "AS" + payment.id() + "R" + refundId,
                amount, payment.providerTransactionId(), null);
        if (full) transactionDao.markRefunded(payment.id());
        return payment.channel();
    }

    private void submitRefund(String kind, PaymentTransaction payment, long refundId, String number, BigDecimal amount,
                              String providerId, com.example.takeout.service.ExternalRefundAttemptService.Cancellation cancellation) {
        PaymentGateway gateway = requireGateway(payment.channel());
        var attempt = refundAttempts.prepare(kind, payment, refundId, number, amount, providerId, cancellation);
        if ("REQUESTED".equals(attempt.status())) {
            gateway.refund(payment.outTradeNo(), number, amount, payment.amount());
            refundAttempts.confirmed(number);
        }
        refundAttempts.doneAfterCommit(number);
    }

    /** Stored provider identity and amount were verified before the independent LATE intent was written. */
    public void recoverLateRefund(com.example.takeout.service.ExternalRefundAttemptService.Attempt attempt) {
        if (!"LATE".equals(attempt.kind())) throw new IllegalArgumentException("Not a late payment refund");
        transactions.executeWithoutResult(status -> {
            applyVerifiedNotice(attempt.channel(), new PaymentGateway.VerifiedNotice(attempt.outTradeNo(),
                    attempt.providerTransactionId(), amountFen(attempt.originalAmount()), "CNY", true));
            refundAttempts.doneAfterCommit(attempt.refundNo());
        });
    }

    public boolean hasPendingPayment(long orderId) {
        return transactionDao.findActiveByOrder(orderId).isPresent();
    }

    private PaymentLaunch createPrepay(PaymentGateway gateway, PaymentTransaction payment, String orderNo) {
        try {
            return transactions.execute(status -> {
                Order locked = orderDao.findByIdForUpdate(payment.orderId())
                        .orElseThrow(() -> new BizException("订单不存在"));
                if (locked.status() != 0 || isExpired(locked.createTime())) throw new BizException("订单已无法支付");
                PaymentTransaction current = transactionDao.findActiveByOrder(payment.orderId()).orElse(null);
                if (current == null || current.id() != payment.id()) {
                    throw new BizException(409, "支付请求已更新，请刷新后重试");
                }
                if (!blank(current.paymentUrl())) return launch(current);
                LocalDateTime expiresAt = LocalDateTime.parse(locked.createTime(), TIME_FORMAT)
                        .plusMinutes(Math.max(1, payTimeoutMinutes));
                String url = "APP".equals(payment.paymentMode())
                        ? gateway.createAppPayment(payment.outTradeNo(), "外卖订单 " + orderNo, payment.amount(), expiresAt)
                        : gateway.createQrPayment(payment.outTradeNo(), "外卖订单 " + orderNo, payment.amount(), expiresAt);
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

    private static String newOutTradeNo(String channel, long orderId) {
        StringBuilder suffix = new StringBuilder(10);
        for (int i = 0; i < 10; i++) suffix.append(TRADE_CHARS[RANDOM.nextInt(TRADE_CHARS.length)]);
        char prefix = PaymentChannels.WECHAT.equals(channel) ? 'W' : 'A';
        return prefix + Long.toUnsignedString(orderId, 32) + suffix;
    }

    private static String refundNo(PaymentTransaction payment) {
        return "R" + payment.outTradeNo();
    }

    private static String now() {
        return LocalDateTime.now().format(TIME_FORMAT);
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

    public enum NotificationResult { PAID, DUPLICATE, REFUNDED }
}
