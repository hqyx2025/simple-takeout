package com.example.takeout.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

class ProductionPaymentGuardTest {
    @Test
    void missingSecretsAndSandboxDefaultsCannotStartProductionPayment() {
        PaymentProperties properties = new PaymentProperties();
        properties.setRealEnabled(true);
        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> new ProductionPaymentGuard(properties));

        assertTrue(error.getMessage().contains("TAKEOUT_ALIPAY_APP_PRIVATE_KEY"));
        assertTrue(error.getMessage().contains("TAKEOUT_ALIPAY_PUBLIC_KEY"));
        assertTrue(error.getMessage().contains("ALIPAY only"));
        assertTrue(error.getMessage().contains("WECHAT is disabled"));
    }

    @Test void disabledExternalPaymentsNeedNoProviderAndMockCannotBeEnabled() {
        var properties = new PaymentProperties();
        properties.setSandbox(false);
        assertDoesNotThrow(() -> new ProductionPaymentGuard(properties));
        properties.setMockEnabled(true);
        assertThrows(IllegalStateException.class, () -> new ProductionPaymentGuard(properties));
    }

    @Test void sandboxUsesTheSamePaymentFlowButMustHaveMatchingCredentialsAndGateway() {
        var properties = new PaymentProperties();
        properties.setSandbox(true);
        var alipay = properties.getAlipay();
        alipay.setAppId("sandbox-app"); alipay.setSellerId("sandbox-seller");
        alipay.setAppPrivateKey("test-only-private-key"); alipay.setPublicKey("test-only-public-key");
        alipay.setNotifyUrl("https://example.test/api/payment/alipay/notify");
        alipay.setGatewayUrl("https://openapi-sandbox.dl.alipaydev.com/gateway.do");
        assertDoesNotThrow(() -> new ProductionPaymentGuard(properties));
        alipay.setGatewayUrl("https://openapi.alipay.com/gateway.do");
        assertThrows(IllegalStateException.class, () -> new ProductionPaymentGuard(properties));
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
