package com.example.takeout.security;

import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;
import static org.junit.jupiter.api.Assertions.*;

class ClaimTrafficConfigurationTest {
    @Configuration(proxyBeanMethods=false)
    @EnableConfigurationProperties(ClaimTrafficSettings.class)
    static class Config { }

    @Test void bindsCanonicalConstructorWithDefaultsAndIndependentOrderBudget() {
        new ApplicationContextRunner().withUserConfiguration(Config.class)
                .withPropertyValues("takeout.claim-traffic.order-per-second=100")
                .run(context -> {
                    assertNull(context.getStartupFailure());
                    var settings=context.getBean(ClaimTrafficSettings.class);
                    assertEquals(100,settings.orderPerSecond());
                    assertEquals(250,settings.paymentPerSecond());
                    assertEquals(4,settings.maxConcurrentPerInstance());
                });
    }
}
