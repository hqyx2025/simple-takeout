package com.example.takeout.config;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/** Production supports ALIPAY only; WECHAT remains hard-disabled until durable asynchronous refund handling exists. */
@Component
@Profile("production")
public class ProductionPaymentGuard {

    public ProductionPaymentGuard(PaymentProperties properties) {
        List<String> missing = new ArrayList<>();
        if (!properties.isRealEnabled()) missing.add("TAKEOUT_PAYMENT_REAL_ENABLED=true");
        if (properties.isMockEnabled()) missing.add("TAKEOUT_PAYMENT_MOCK_ENABLED=false");
        if (properties.isSandbox()) missing.add("TAKEOUT_PAYMENT_SANDBOX=false");

        PaymentProperties.Alipay alipay = properties.getAlipay();
        require(missing, alipay.getAppId(), "TAKEOUT_ALIPAY_APP_ID");
        require(missing, alipay.getSellerId(), "TAKEOUT_ALIPAY_SELLER_ID");
        require(missing, alipay.getAppPrivateKey(), "TAKEOUT_ALIPAY_APP_PRIVATE_KEY");
        require(missing, alipay.getPublicKey(), "TAKEOUT_ALIPAY_PUBLIC_KEY");
        require(missing, https(alipay.getNotifyUrl()), "TAKEOUT_ALIPAY_NOTIFY_URL (HTTPS)");
        require(missing, "https://openapi.alipay.com/gateway.do".equals(alipay.getGatewayUrl()),
                "TAKEOUT_ALIPAY_GATEWAY_URL (production gateway)");

        if (!missing.isEmpty()) {
            throw new IllegalStateException("Production payment supports ALIPAY only; WECHAT is disabled until " +
                    "durable asynchronous refunds are implemented. Configure: " + String.join(", ", missing));
        }
    }

    private static boolean https(String value) {
        return value != null && value.startsWith("https://");
    }

    private static void require(List<String> missing, String value, String name) {
        if (value == null || value.isBlank()) missing.add(name);
    }

    private static void require(List<String> missing, boolean valid, String name) {
        if (!valid) missing.add(name);
    }

}
