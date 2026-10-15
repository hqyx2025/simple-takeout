package com.example.takeout.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration
@Profile("production")
public class ProductionHuaweiGuard {
    public ProductionHuaweiGuard(@Value("${takeout.sms.provider}") String smsProvider,
                                 @Value("${takeout.upload.provider}") String uploadProvider) {
        if (!"huawei".equals(smsProvider) || !"obs".equals(uploadProvider)) {
            throw new IllegalStateException("Production requires Huawei Cloud SMS and OBS; mock/local providers are disabled");
        }
    }
}
