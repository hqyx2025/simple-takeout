package com.example.takeout.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("!production")
public class DemoModeWarning {

    private static final Logger log = LoggerFactory.getLogger(DemoModeWarning.class);

    public DemoModeWarning(@Value("${takeout.sms.expose-mock-code:false}") boolean exposeMockCode,
                           @Value("${takeout.demo.recharge-enabled:false}") boolean demoRechargeEnabled) {
        if (exposeMockCode || demoRechargeEnabled) {
            log.warn("演示安全功能已开启（短信验证码回传={}, 演示充值={}），禁止对外部署",
                    exposeMockCode, demoRechargeEnabled);
        }
    }
}
