package com.example.takeout.service.thirdparty;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Locale;
import java.util.Set;

/**
 * 支付渠道（Mock 适配层）：微信/支付宝走余额 + 模拟异步回调，真实接入时在此替换为对应 SDK 网关。
 */
public final class PaymentChannels {

    private static final Logger log = LoggerFactory.getLogger(PaymentChannels.class);

    public static final String BALANCE = "BALANCE";
    public static final String ALIPAY = "ALIPAY";
    public static final String WECHAT = "WECHAT";
    public static final Set<String> SUPPORTED = Set.of(BALANCE, ALIPAY, WECHAT);

    private PaymentChannels() {
    }

    /** 空 / 未知渠道归一为余额（旧客户端不传 channel）。 */
    public static String normalize(String channel) {
        if (channel == null || channel.isBlank()) {
            return BALANCE;
        }
        String normalized = channel.trim().toUpperCase(Locale.ROOT);
        return SUPPORTED.contains(normalized) ? normalized : BALANCE;
    }

    public static boolean isMockThirdParty(String channel) {
        return ALIPAY.equals(channel) || WECHAT.equals(channel);
    }

    /** 模拟第三方支付异步回调（真实渠道回调来自支付平台，Mock 落地为日志）。 */
    public static void logMockCallback(String channel, long orderId) {
        log.info("[Mock第三方支付] 订单 {} 模拟调起 {} 支付 → 下单成功 → 异步回调支付成功", orderId, channel);
    }
}
