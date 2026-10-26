package com.example.takeout.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class DemoModeWarning {

    @org.springframework.beans.factory.annotation.Autowired
    void requireSafeRuntime(@Value("${takeout.sms.provider:qq-email}") String provider,
                            @Value("${takeout.security.rate-limit.enabled:true}") boolean rateLimitEnabled) {
        if (!"qq-email".equals(provider) || !rateLimitEnabled) {
            throw new IllegalStateException("所有 profile 均须启用真实邮件验证和限流");
        }
    }

    public DemoModeWarning(@Value("${takeout.sms.expose-mock-code:false}") boolean exposeMockCode,
                           @Value("${takeout.demo.recharge-enabled:false}") boolean demoRechargeEnabled) {
        if (exposeMockCode || demoRechargeEnabled) {
            throw new IllegalStateException("验证码回传与演示充值已停用，请关闭相关配置");
        }
    }
}
