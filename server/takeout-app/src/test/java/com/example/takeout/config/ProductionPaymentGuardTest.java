package com.example.takeout.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

class ProductionPaymentGuardTest {
    @Test
    void missingSecretsAndSandboxDefaultsCannotStartProductionPayment() {
        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> new ProductionPaymentGuard(new PaymentProperties()));

        assertTrue(error.getMessage().contains("TAKEOUT_ALIPAY_APP_PRIVATE_KEY"));
        assertTrue(error.getMessage().contains("TAKEOUT_ALIPAY_PUBLIC_KEY"));
        assertTrue(error.getMessage().contains("TAKEOUT_PAYMENT_SANDBOX=false"));
        assertTrue(error.getMessage().contains("ALIPAY only"));
        assertTrue(error.getMessage().contains("WECHAT is disabled"));
    }

    @Test
    void productionAlipayDoesNotRequireCredentialsForTheHardDisabledWechatChannel() {
        PaymentProperties properties = new PaymentProperties();
        properties.setRealEnabled(true);
        properties.setSandbox(false);
        var alipay = properties.getAlipay();
        alipay.setAppId("production-app");
        alipay.setSellerId("production-seller");
        alipay.setAppPrivateKey("test-only-private-key");
        alipay.setPublicKey("test-only-public-key");
        alipay.setGatewayUrl("https://openapi.alipay.com/gateway.do");
        alipay.setNotifyUrl("https://example.test/api/payment/alipay/notify");

        assertDoesNotThrow(() -> new ProductionPaymentGuard(properties));
    }
}
