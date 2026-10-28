package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.example.takeout.model.Order;
import com.example.takeout.model.RefundReason;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.service.mq.DomainEventPublisher;
import com.example.takeout.service.thirdparty.ExternalPaymentService;
import com.example.takeout.service.thirdparty.PaymentChannels;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.Map;

@Service
public class AfterSalesService {
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private final OrderDao orders;
    private final StoreDao stores;
    private final RefundDao refunds;
    private final AfterSalesDao ledger;
    private final ExternalPaymentService payments;
    private final PaymentRecordDao paymentRecords;
    private final DomainEventPublisher events;
    private final ObjectMapper json;
    @org.springframework.beans.factory.annotation.Autowired
    private ExternalRefundAttemptService refundAttempts;

    void configureRefundAttempts(ExternalRefundAttemptService attempts) { this.refundAttempts = attempts; }

    public AfterSalesService(OrderDao orders, StoreDao stores, RefundDao refunds, AfterSalesDao ledger,
                             ExternalPaymentService payments, PaymentRecordDao paymentRecords,
                             DomainEventPublisher events, ObjectMapper json) {
        this.orders = orders;
        this.stores = stores;
        this.refunds = refunds;
        this.ledger = ledger;
        this.payments = payments;
        this.paymentRecords = paymentRecords;
        this.events = events;
        this.json = json;
    }

    public BigDecimal remainingRefund(Order order) {
        return money(order.payAmount()).subtract(refunds.refundedAmount(order.id())).max(BigDecimal.ZERO);
    }

    public BigDecimal merchantRefunded(Order order) { return refunds.merchantRefunded(order.id()); }

    public BigDecimal netPaid(long userId) { return ledger.netPaid(userId); }

    public LocalDateTime eligibleUntil(Order order) {
        if (order.completeTime() == null || order.completeTime().isBlank()) return null;
        try { return LocalDateTime.parse(order.completeTime(), TIME).plusHours(48); }
        catch (DateTimeParseException error) { return null; }
    }

    public boolean canApply(Order order) {
        LocalDateTime until = eligibleUntil(order);
        return order.status() == 4 && (order.escrowStatus() == 0 || order.escrowStatus() == 1)
                && until != null && !LocalDateTime.now().isAfter(until) && remainingRefund(order).signum() > 0
                && refunds.latestByOrder(order.id()).filter(record -> "REJECTED".equals(record.status())).isEmpty();
    }

    public List<RefundRecord> history(long userId, long orderId) {
        Order order = requireOrder(orderId, false);
        if (order.userId() != userId) throw new BizException(403, "无权查看该订单");
        return refunds.listByOrder(orderId);
    }

    public List<RefundRecord> merchantHistory(long merchantId, long orderId) {
        Order order = requireOrder(orderId, false);
        if (stores.findById(order.storeId()).orElseThrow(() -> new BizException("店铺不存在")).ownerId() != merchantId)
            throw new BizException(403, "无权查看该订单");
        return refunds.listByOrder(orderId);
    }

    @Transactional
    public RefundRecord apply(long userId, long orderId, String reasonType, String reason,
                              String key, BigDecimal amount, List<String> evidence) {
        Order order = requireOrder(orderId, true);
        if (order.userId() != userId) throw new BizException(403, "无权操作该订单");
        String requestKey = key == null || key.isBlank() ? null : text(key, 128, "退款请求标识");
        if (requestKey != null) {
            var replay = refunds.findByRequestKey(orderId, requestKey);
            if (replay.isPresent()) return replay.get();
        }
        var pending = refunds.findPending(orderId);
        if (pending.isPresent()) {
            if (requestKey != null) refunds.bindApplyRequest(orderId, requestKey, pending.get().id());
            return pending.get();
        }
        RefundReason type = RefundReason.fromCode(reasonType);
        if (type == null) throw new BizException("退款原因类型无效");
        String safeReason = text(reason, 255, "退款原因");
        if (type == RefundReason.OTHER && safeReason.isBlank()) throw new BizException("选择其他原因时，请说明具体问题");
        requireEligible(order);
        if (refunds.latestByOrder(orderId).filter(record -> "REJECTED".equals(record.status())).isPresent())
            throw new BizException("退款已驳回，请使用一次申诉机会");
        BigDecimal remaining = remainingRefund(order);
        BigDecimal requested = amount == null ? remaining : exactAmount(amount);
        if (requested.signum() <= 0 || requested.compareTo(remaining) > 0) throw new BizException("退款金额必须大于0且不超过剩余可退金额");
        String images = images(evidence);
        long merchantId = stores.findById(order.storeId()).orElseThrow(() -> new BizException("店铺不存在")).ownerId();
        if (!ledger.markPending(orderId, order.escrowStatus())) throw new BizException("订单状态已变化，请刷新后重试");
        long id = refunds.insertAfterSales(orderId, userId, merchantId, type.code(), safeReason, requested,
                now(), requestKey, images, order.escrowStatus());
        if (requestKey != null) refunds.bindApplyRequest(orderId, requestKey, id);
        return requireRefund(id);
    }

    @Transactional
    public RefundRecord appeal(long userId, long orderId, long refundId, String reason, List<String> evidence) {
        Order order = requireOrder(orderId, true);
        if (order.userId() != userId) throw new BizException(403, "无权操作该订单");
        RefundRecord record = refunds.findByIdForUpdate(refundId).orElseThrow(() -> new BizException("退款申请不存在"));
        if (record.orderId() != orderId) throw new BizException(403, "退款申请不属于该订单");
        if (!"REJECTED".equals(record.status()) || record.appealCount() != 0) throw new BizException("仅被驳回的退款可申诉一次");
        if (LocalDateTime.now().isAfter(parseTime(record.processTime()).plusHours(48))) throw new BizException("已超过驳回后48小时申诉期限");
        String note = text(reason, 255, "申诉原因");
        if (note.isBlank()) throw new BizException("请填写申诉原因");
        if (order.status() != 4 || order.escrowStatus() == 2 || refunds.findPending(orderId).isPresent()
                || record.amount().compareTo(remainingRefund(order)) > 0) throw new BizException("订单当前不可申诉");
        if (!ledger.markPending(orderId, order.escrowStatus()) ||
                !refunds.appeal(refundId, note, images(evidence), order.escrowStatus(), now())) throw new BizException("退款状态已变化");
        return requireRefund(refundId);
    }

    @Transactional
    public RefundRecord merchantEvidence(long merchantId, long refundId, String response, List<String> evidence) {
        RefundRecord initial = requireRefund(refundId);
        requireOrder(initial.orderId(), true);
        RefundRecord record = refunds.findByIdForUpdate(refundId).orElseThrow(() -> new BizException("退款申请不存在"));
        if (record.merchantId() != merchantId) throw new BizException(403, "无权操作该售后");
        String note = text(response, 1000, "商家说明");
        String images = images(evidence);
        if (note.isBlank() && (evidence == null || evidence.isEmpty())) throw new BizException("请填写说明或上传证据");
        if (!refunds.merchantEvidence(refundId, note, images)) throw new BizException("该退款申请已处理");
        return requireRefund(refundId);
    }

    @Transactional
    public RefundRecord approve(long refundId) {
        RefundRecord initial = requireRefund(refundId);
        Order order = requireOrder(initial.orderId(), true);
        RefundRecord record = lockPending(refundId);
        if (order.status() != 6 || order.escrowStatus() != record.originalEscrow()
                || record.amount().compareTo(remainingRefund(order)) > 0) throw new BizException("订单资金状态已变化");
        BigDecimal net = money(order.payAmount()).subtract(money(order.deliveryFee())).max(BigDecimal.ZERO);
        BigDecimal merchant = record.amount().min(net.subtract(merchantRefunded(order)).max(BigDecimal.ZERO));
        BigDecimal platform = record.amount().subtract(merchant);
        boolean full = record.amount().compareTo(remainingRefund(order)) == 0;
        ledger.lockWallets(order.userId(), record.merchantId());
        BigDecimal deducted = record.originalEscrow() == 1 ? ledger.deductMerchant(record.merchantId(), merchant) : BigDecimal.ZERO.setScale(2);
        BigDecimal debt = record.originalEscrow() == 1 ? merchant.subtract(deducted) : BigDecimal.ZERO.setScale(2);
        String channel = payments.refundOriginalPayment(order, record.amount(), record.id(), full);
        if (PaymentChannels.BALANCE.equals(channel)) ledger.creditCustomer(order.userId(), record.amount());
        String time = now();
        if (!refunds.complete(refundId, merchant, platform, time) || !ledger.finishOrder(order.id(), record.originalEscrow(), full))
            throw new BizException("退款状态已变化");
        ledger.insertLedger(refundId, order.id(), record.merchantId(), merchant, deducted, debt, platform, time);
        paymentRecords.insert(order.id(), order.userId(), record.amount(), "REFUND", channel, "SUCCESS", time);
        events.publish(DomainEventPublisher.ORDER_REFUNDED, order.id(), Map.of("userId", order.userId(), "refundId", refundId,
                "amount", record.amount(), "fullRefund", full));
        return requireRefund(refundId);
    }

    @Transactional
    public RefundRecord reject(long refundId, String reason) {
        String note = text(reason, 255, "拒绝原因");
        if (note.isBlank()) throw new BizException("请填写拒绝原因");
        RefundRecord initial = requireRefund(refundId);
        Order order = requireOrder(initial.orderId(), true);
        RefundRecord record = lockPending(refundId);
        if (refundAttempts != null) refundAttempts.requireRejectable(refundId);
        if (!refunds.updateStatus(refundId, "REJECTED", now(), note) ||
                !ledger.finishOrder(order.id(), record.originalEscrow(), false)) throw new BizException("退款状态已变化");
        return requireRefund(refundId);
    }

    @Transactional
    public void recoverRefund(ExternalRefundAttemptService.Attempt attempt) {
        if (!"AFTER_SALES".equals(attempt.kind())) throw new IllegalArgumentException("Not an after-sales intent");
        requireOrder(attempt.orderId(), true);
        RefundRecord record = refunds.findByIdForUpdate(attempt.refundId()).orElseThrow(() -> new BizException("退款申请不存在"));
        if ("REFUNDED".equals(record.status())) refundAttempts.doneAfterCommit(attempt.refundNo());
        else approve(attempt.refundId());
    }

    /** 调用者持有订单锁并已通过条件更新取得唯一结算权；净货款先偿债，余款入钱包。 */
    @Transactional
    public void payMerchantSettlement(Order order, BigDecimal net) {
        BigDecimal amount = exactAmount(net);
        if (amount.signum() < 0) throw new BizException("商户结算金额不能为负数");
        long merchantId = stores.findById(order.storeId()).orElseThrow(() -> new BizException("店铺不存在")).ownerId();
        ledger.payMerchantSettlement(order.id(), merchantId, amount, now());
    }

    public LedgerPage merchantLedger(long merchantId, int page, int pageSize) {
        int size = Math.clamp(pageSize, 1, 100), current = Math.max(page, 1);
        int total = ledger.countLedger(merchantId);
        return new LedgerPage(ledger.ledger(merchantId, size, (long) (current - 1) * size), total,
                current, size, (long) current * size < total, ledger.debtAmount(merchantId));
    }

    public record LedgerPage(List<AfterSalesDao.LedgerEntry> list, int total, int page, int pageSize,
                             boolean hasMore, BigDecimal debtAmount) {}

    private void requireEligible(Order order) {
        if (order.status() != 4 || (order.escrowStatus() != 0 && order.escrowStatus() != 1))
            throw new BizException("仅已送达且未全额退款的订单可申请售后");
        LocalDateTime until = eligibleUntil(order);
        if (until == null || LocalDateTime.now().isAfter(until)) throw new BizException("已超过送达后48小时售后期限");
    }

    private Order requireOrder(long id, boolean lock) {
        return (lock ? orders.findByIdForUpdate(id) : orders.findById(id)).orElseThrow(() -> new BizException("订单不存在"));
    }

    private RefundRecord requireRefund(long id) {
        return refunds.findById(id).orElseThrow(() -> new BizException("退款申请不存在"));
    }

    private RefundRecord lockPending(long id) {
        RefundRecord record = refunds.findByIdForUpdate(id).orElseThrow(() -> new BizException("退款申请不存在"));
        if (!"PENDING".equals(record.status())) throw new BizException("该退款申请已处理");
        return record;
    }

    private String images(List<String> values) {
        List<String> images = values == null ? List.of() : values;
        if (images.size() > 9) throw new BizException("证据图片最多9张");
        for (String path : images) {
            if (path == null || path.length() > 512 || !path.matches("/uploads/[A-Za-z0-9_./-]+") || path.contains(".."))
                throw new BizException("证据图片必须使用已上传图片的相对地址");
        }
        try { return json.writeValueAsString(images); }
        catch (JsonProcessingException error) { throw new BizException("证据图片格式无效"); }
    }

    private static String text(String value, int max, String label) {
        String result = value == null ? "" : value.trim();
        if (result.length() > max) throw new BizException(label + "最多 " + max + " 个字符");
        return result;
    }

    private static BigDecimal exactAmount(BigDecimal value) {
        try { return value.setScale(2, RoundingMode.UNNECESSARY); }
        catch (ArithmeticException error) { throw new BizException("退款金额最多两位小数"); }
    }

    private static BigDecimal money(double value) { return BigDecimal.valueOf(value).setScale(2, RoundingMode.HALF_UP); }
    private static LocalDateTime parseTime(String value) {
        try { return LocalDateTime.parse(value == null ? "" : value, TIME); }
        catch (DateTimeParseException error) { throw new BizException("订单或售后时间无效，请联系管理员"); }
    }
    private static String now() { return LocalDateTime.now().format(TIME); }
}
