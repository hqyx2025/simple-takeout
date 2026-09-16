package com.example.takeout.service.thirdparty;

/**
 * 短信发送适配（Mock 适配层）：真实短信服务商可替换实现（阿里云短信 / 腾讯云短信）。
 */
public interface SmsSender {
    /** 向指定手机号发送验证码，返回验证码内容（Mock 实现为固定码）。 */
    String sendSmsCode(String phone);
}
