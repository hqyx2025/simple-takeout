package com.example.takeout.security;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import static org.junit.jupiter.api.Assertions.*;

class Round3LoginConfigurationTest {
    private final ApplicationContextRunner runner = new ApplicationContextRunner().withUserConfiguration(LoginRateLimiter.class);
    @Test void sourceAndTotalAndAccountThresholdsUseActualRuntimeProperties() {
        runner.withPropertyValues("takeout.security.rate-limit.login-failure-limit=2",
                "takeout.security.rate-limit.login-total-limit=3", "takeout.security.rate-limit.login-account-limit=4")
                .run(context -> {
                    assertNull(context.getStartupFailure());
                    var limiter = context.getBean(LoginRateLimiter.class);
                    for (int i = 0; i < 2; i++) limiter.recordAttempt("login", "192.0.2.175");
                    assertTrue(limiter.isBlocked("login", "192.0.2.175"));
                    for (int i = 0; i < 3; i++) limiter.recordAttempt("login-total", "192.0.2.176");
                    assertTrue(limiter.isBlocked("login-total", "192.0.2.176"));
                    for (int i = 0; i < 4; i++) limiter.recordAttempt("login-account-fail", "u975");
                    assertTrue(limiter.isBlocked("login-account-fail", "u975"));
                    System.out.println("[RT-17/config] configured source-fail=2 total=3 account=4 all enforced");
                });
    }
    @Test void invalidThresholdFailsStartupInsteadOfSilentlyDisablingProtection() {
        runner.withPropertyValues("takeout.security.rate-limit.login-failure-limit=0")
                .run(context -> assertNotNull(context.getStartupFailure()));
        System.out.println("[RT-17/config] zero failure threshold -> startup rejected");
    }
}
