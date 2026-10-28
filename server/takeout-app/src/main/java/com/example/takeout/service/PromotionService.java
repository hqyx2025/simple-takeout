package com.example.takeout.service;

import com.example.takeout.model.MarketingActivity;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Comparator;
import java.util.List;

/** One price policy: best rate, first-paid-order reduction, coupon; gift threshold uses goods after rate. */
@Service
public class PromotionService {
    public record Quote(BigDecimal goodsAfterRate, BigDecimal newCustomerDiscount, long rateActivityId,
                        long newCustomerActivityId) {
        public BigDecimal discount(BigDecimal original, BigDecimal coupon) {
            return cents(original.subtract(goodsAfterRate).add(newCustomerDiscount).add(coupon));
        }
    }
    private final JdbcTemplate db;
    private final ObjectMapper json;
    public PromotionService(JdbcTemplate db, ObjectMapper json) { this.db = db; this.json = json; }

    public Quote quote(long user, long store, BigDecimal original, List<MarketingActivity> activities) {
        boolean hasNewcomer = activities.stream().anyMatch(a -> "NEW_USER".equals(a.type()) && a.reduceAmount() > 0);
        return calculate(original, activities, hasNewcomer && reserveFirstPaidOrder(user, store));
    }

    public static Quote calculate(BigDecimal original, List<MarketingActivity> activities, boolean firstPaidOrder) {
        MarketingActivity rate = activities.stream().filter(a -> "DISCOUNT".equals(a.type())
                && a.discountRate() > 0 && a.discountRate() < 1)
                .min(Comparator.comparingDouble(MarketingActivity::discountRate).thenComparingLong(MarketingActivity::id)).orElse(null);
        BigDecimal afterRate = rate == null ? cents(original) : cents(original.multiply(BigDecimal.valueOf(rate.discountRate())));
        MarketingActivity newcomer = activities.stream().filter(a -> "NEW_USER".equals(a.type()) && a.reduceAmount() > 0)
                .sorted(Comparator.comparingDouble(MarketingActivity::reduceAmount).reversed().thenComparingLong(MarketingActivity::id))
                .findFirst().orElse(null);
        return new Quote(afterRate, firstPaidOrder && newcomer != null ? cents(BigDecimal.valueOf(newcomer.reduceAmount())) : BigDecimal.ZERO,
                rate == null ? 0 : rate.id(), firstPaidOrder && newcomer != null ? newcomer.id() : 0);
    }

    private boolean reserveFirstPaidOrder(long user, long store) {
        db.update("INSERT INTO promotion_claims(user_id,store_id) VALUES(?,?) ON DUPLICATE KEY UPDATE user_id=user_id", user, store);
        var claim = db.queryForMap("SELECT state FROM promotion_claims WHERE user_id=? AND store_id=? FOR UPDATE", user, store);
        if (!"AVAILABLE".equals(claim.get("state"))) return false;
        Integer paid = db.queryForObject("SELECT COUNT(*) FROM orders WHERE user_id=? AND store_id=? AND pay_time<>''", Integer.class, user, store);
        if (paid != null && paid > 0) {
            db.update("UPDATE promotion_claims SET state='USED',updated_at=NOW() WHERE user_id=? AND store_id=?", user, store);
            return false;
        }
        db.update("UPDATE promotion_claims SET state='RESERVED',order_id=0,updated_at=NOW() WHERE user_id=? AND store_id=?", user, store);
        return true;
    }

    public void bind(long user, long store, long order, BigDecimal original, BigDecimal coupon, Quote quote) {
        if (quote.newCustomerActivityId() > 0) {
            if (db.update("UPDATE promotion_claims SET order_id=? WHERE user_id=? AND store_id=? AND state='RESERVED' AND order_id=0",
                    order, user, store) != 1) throw new IllegalStateException("New-customer reservation lost");
        }
        try {
            db.update("INSERT INTO order_pricing_snapshots(order_id,snapshot_json) VALUES(?,?)", order, json.writeValueAsString(
                    java.util.Map.of("version", 1, "originalGoods", original, "goodsAfterRate", quote.goodsAfterRate(),
                            "newCustomerDiscount", quote.newCustomerDiscount(), "couponDiscount", coupon,
                            "rateActivityId", quote.rateActivityId(), "newCustomerActivityId", quote.newCustomerActivityId(),
                            "order", "BEST_RATE_THEN_FIRST_PAID_ORDER_THEN_COUPON", "giftThresholdBasis", "GOODS_AFTER_RATE")));
        } catch (com.fasterxml.jackson.core.JsonProcessingException e) { throw new IllegalStateException(e); }
    }
    public void paid(long order) {
        db.update("UPDATE promotion_claims SET state='USED',updated_at=NOW() WHERE order_id=? AND state='RESERVED'", order);
    }
    public void releaseUnpaid(long order) {
        db.update("UPDATE promotion_claims SET state='AVAILABLE',order_id=0,updated_at=NOW() WHERE order_id=? AND state='RESERVED'", order);
    }
    public static BigDecimal cents(BigDecimal value) { return value.setScale(2, RoundingMode.HALF_UP); }
}
