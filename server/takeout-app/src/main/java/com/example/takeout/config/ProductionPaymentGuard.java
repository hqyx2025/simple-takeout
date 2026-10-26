package com.example.takeout.config;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/** 所有 profile 均校验已启用的支付宝渠道；按项目约定保留沙箱与余额支付。 */
@Component
public class ProductionPaymentGuard {

    public ProductionPaymentGuard(PaymentProperties properties) {
        if (properties.isMockEnabled()) throw new IllegalStateException("模拟支付已停用，任何 profile 均须关闭");
        if (!properties.isRealEnabled() && !properties.isSandbox()) return;
        List<String> missing = new ArrayList<>();

        PaymentProperties.Alipay alipay = properties.getAlipay();
        require(missing, alipay.getAppId(), "TAKEOUT_ALIPAY_APP_ID");
        require(missing, alipay.getSellerId(), "TAKEOUT_ALIPAY_SELLER_ID");
        require(missing, alipay.getAppPrivateKey(), "TAKEOUT_ALIPAY_APP_PRIVATE_KEY");
        require(missing, alipay.getPublicKey(), "TAKEOUT_ALIPAY_PUBLIC_KEY");
        require(missing, https(alipay.getNotifyUrl()), "TAKEOUT_ALIPAY_NOTIFY_URL (HTTPS)");
        String expectedGateway = properties.isSandbox() ? "https://openapi-sandbox.dl.alipaydev.com/gateway.do"
                : "https://openapi.alipay.com/gateway.do";
        require(missing, expectedGateway.equals(alipay.getGatewayUrl()),
                "TAKEOUT_ALIPAY_GATEWAY_URL (must match sandbox setting)");

        if (!missing.isEmpty()) {
            throw new IllegalStateException("Payment supports ALIPAY only; WECHAT is disabled until " +
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
