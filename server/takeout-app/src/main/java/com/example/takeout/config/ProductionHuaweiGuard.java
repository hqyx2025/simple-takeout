package com.example.takeout.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.context.annotation.Configuration;

/** Require real email verification and OBS in production. */
@Configuration
@Profile("production")
public class ProductionHuaweiGuard {
    public ProductionHuaweiGuard(@Value("${takeout.sms.provider}") String smsProvider,
                                 @Value("${takeout.upload.provider}") String uploadProvider,
                                 @Value("${takeout.sms.expose-mock-code:false}") boolean exposeMockCode,
                                 @Value("${takeout.demo.recharge-enabled:false}") boolean demoRechargeEnabled) {
        if (!"qq-email".equals(smsProvider) || !"obs".equals(uploadProvider)) {
            throw new IllegalStateException("Production requires QQ SMTP and OBS; mock/local providers are disabled");
        }
        if (exposeMockCode || demoRechargeEnabled) {
            throw new IllegalStateException("Production must disable TAKEOUT_SMS_EXPOSE_MOCK_CODE and " +
                    "TAKEOUT_DEMO_RECHARGE_ENABLED");
        }
    }
}
