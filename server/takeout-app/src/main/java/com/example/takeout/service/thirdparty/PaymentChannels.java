package com.example.takeout.service.thirdparty;

import java.util.Locale;
import java.util.Set;

/** 支付渠道；只有 BALANCE 可以扣除账户余额，第三方渠道必须经网关确认。 */
public final class PaymentChannels {

    public static final String BALANCE = "BALANCE";
    public static final String ALIPAY = "ALIPAY";
    public static final String WECHAT = "WECHAT";
    public static final Set<String> SUPPORTED = Set.of(BALANCE, ALIPAY, WECHAT);

    private PaymentChannels() {
    }

    /** 空值和未知渠道保留为无效值，禁止隐式回退到余额扣款。 */
    public static String normalize(String channel) {
        return channel == null ? "" : channel.trim().toUpperCase(Locale.ROOT);
    }

    public static boolean isThirdParty(String channel) {
        return ALIPAY.equals(channel) || WECHAT.equals(channel);
    }

}
