package com.example.takeout.service.thirdparty;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/** 短信 Mock：固定验证码 123456 + 日志。真实接入时替换为短信服务商 SDK 实现。 */
@Service
public class MockSmsSender implements SmsSender {

    private static final Logger log = LoggerFactory.getLogger(MockSmsSender.class);

    @Override
    public String sendSmsCode(String phone) {
        String code = "123456";
        log.info("[Mock短信] 向 {} 发送验证码：{}", phone, code);
        return code;
    }
}
