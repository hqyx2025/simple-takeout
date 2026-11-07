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
        @DefaultValue("30s") Duration orderLease) {
    public ClaimTrafficSettings {
        if (maxConcurrentPerInstance < 1 || maxConcurrentPerInstance > 128
                || couponPerSecond < 1 || couponPerSecond > 10000 || riderPerSecond < 1 || riderPerSecond > 10000
                || databaseFailureThreshold < 1 || databaseFailureThreshold > 100
                || invalid(databaseCooldown) || invalid(redisCooldown) || invalid(orderLease)) {
            throw new IllegalArgumentException("领券/抢单流量保护配置超出允许范围");
        }
    }
    private static boolean invalid(Duration value) {
        return value == null || value.compareTo(Duration.ofMillis(100)) < 0 || value.compareTo(Duration.ofMinutes(5)) > 0;
    }
}
