package com.example.takeout.service;

public interface SmsCodeVerifier {
    /** Validate without spending a code; implementations without this capability must fail closed. */
    default void verify(String identity, String code) {
        throw new com.example.takeout.common.BizException(503, "验证码服务暂不可用，请稍后重试");
    }

    void consume(String identity, String code);
}
