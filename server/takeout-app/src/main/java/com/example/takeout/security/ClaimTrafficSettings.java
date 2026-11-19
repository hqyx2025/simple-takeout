package com.example.takeout.security;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;
import java.time.Duration;

@ConfigurationProperties("takeout.claim-traffic")
public record ClaimTrafficSettings(
        @DefaultValue("4") int maxConcurrentPerInstance,
        @DefaultValue("20") int couponPerSecond,
        @DefaultValue("30") int riderPerSecond,
        @DefaultValue("3") int databaseFailureThreshold,
        @DefaultValue("5s") Duration databaseCooldown,
        @DefaultValue("5s") Duration redisCooldown,
        @DefaultValue("30s") Duration orderLease,
        @DefaultValue("250") int orderPerSecond,
        @DefaultValue("250") int paymentPerSecond,
        @DefaultValue("6") int orderConcurrentPerInstance,
        @DefaultValue("4") int paymentConcurrentPerInstance) {
    public ClaimTrafficSettings(int capacity, int coupon, int rider, int failures, Duration dbCooldown,
                                Duration redisCooldown, Duration lease) {
        this(capacity, coupon, rider, failures, dbCooldown, redisCooldown, lease, 250, 250, 6, 4);
    }
    @org.springframework.boot.context.properties.bind.ConstructorBinding
    public ClaimTrafficSettings {
        if (maxConcurrentPerInstance < 1 || maxConcurrentPerInstance > 128
                || couponPerSecond < 1 || couponPerSecond > 10000 || riderPerSecond < 1 || riderPerSecond > 10000
                || databaseFailureThreshold < 1 || databaseFailureThreshold > 100
                || orderPerSecond < 1 || orderPerSecond > 10000 || paymentPerSecond < 1 || paymentPerSecond > 10000
                || orderConcurrentPerInstance < 1 || orderConcurrentPerInstance > 128
                || paymentConcurrentPerInstance < 1 || paymentConcurrentPerInstance > 128
                || invalid(databaseCooldown) || invalid(redisCooldown) || invalid(orderLease)) {
            throw new IllegalArgumentException("领券/抢单流量保护配置超出允许范围");
        }
    }
    private static boolean invalid(Duration value) {
        return value == null || value.compareTo(Duration.ofMillis(100)) < 0 || value.compareTo(Duration.ofMinutes(5)) > 0;
    }
}
