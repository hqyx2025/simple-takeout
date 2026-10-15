package com.example.takeout.service.thirdparty;

import org.junit.jupiter.api.Test;

import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** 支付渠道契约：缺失或未知渠道不回退余额，支付宝/微信是第三方渠道。 */
class PaymentChannelsTest {

    @Test
    void defaultsMissingChannelToBalanceAndPreservesUnknownForRejection() {
        assertEquals("", PaymentChannels.normalize(null));
        assertEquals("", PaymentChannels.normalize("  "));
        assertEquals("UNKNOWN", PaymentChannels.normalize("unknown"));
        assertEquals("ALIPAY", PaymentChannels.normalize("alipay"));
        assertEquals("WECHAT", PaymentChannels.normalize("WeChat"));
    }

    @Test
    void marksThirdPartyChannels() {
        assertFalse(PaymentChannels.isThirdParty("BALANCE"));
        assertTrue(PaymentChannels.isThirdParty("ALIPAY"));
        assertTrue(PaymentChannels.isThirdParty("WECHAT"));
    }

    @Test
    void supportedSetContainsThreeChannels() {
        assertTrue(PaymentChannels.SUPPORTED.containsAll(Set.of("BALANCE", "ALIPAY", "WECHAT")));
    }
}
