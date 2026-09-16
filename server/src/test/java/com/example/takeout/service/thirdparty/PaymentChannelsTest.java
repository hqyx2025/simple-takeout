package com.example.takeout.service.thirdparty;

import org.junit.jupiter.api.Test;

import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Mock 支付渠道契约：空/未知归一为余额，微信/支付宝标记为第三方模拟渠道。 */
class PaymentChannelsTest {

    @Test
    void normalizesBlankAndUnknownToBalance() {
        assertEquals("BALANCE", PaymentChannels.normalize(null));
        assertEquals("BALANCE", PaymentChannels.normalize("  "));
        assertEquals("BALANCE", PaymentChannels.normalize("unknown"));
        assertEquals("ALIPAY", PaymentChannels.normalize("alipay"));
        assertEquals("WECHAT", PaymentChannels.normalize("WeChat"));
    }

    @Test
    void marksThirdPartyChannels() {
        assertFalse(PaymentChannels.isMockThirdParty("BALANCE"));
        assertTrue(PaymentChannels.isMockThirdParty("ALIPAY"));
        assertTrue(PaymentChannels.isMockThirdParty("WECHAT"));
    }

    @Test
    void supportedSetContainsThreeChannels() {
        assertTrue(PaymentChannels.SUPPORTED.containsAll(Set.of("BALANCE", "ALIPAY", "WECHAT")));
    }
}
