package com.example.takeout.service.thirdparty;

import com.alipay.api.AlipayApiException;
import com.alipay.api.internal.util.AlipaySignature;
import com.example.takeout.config.PaymentProperties;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.math.BigDecimal;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AlipayGatewayTest {

    private static final String APP_ID = "test-app";
    private static final String SELLER_ID = "test-seller";
    private static String privateKey;
    private static String publicKey;
    private AlipayGateway gateway;

    @BeforeAll
    static void generateSigningKey() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        KeyPair keyPair = generator.generateKeyPair();
        privateKey = Base64.getEncoder().encodeToString(keyPair.getPrivate().getEncoded());
        publicKey = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());
    }

    @BeforeEach
    void setUp() {
        PaymentProperties properties = new PaymentProperties();
        properties.getAlipay().setAppId(APP_ID);
        properties.getAlipay().setSellerId(SELLER_ID);
        properties.getAlipay().setPublicKey(publicKey);
        properties.getAlipay().setAppPrivateKey(privateKey);
        properties.getAlipay().setNotifyUrl("https://example.test/api/payment/alipay/notify");
        gateway = new AlipayGateway(properties);
    }

    @Test
    void createsVerifiableAppOrderLocallyWithTheExactTradeAndAmount() throws Exception {
        String orderInfo = gateway.createAppPayment("APP123", "外卖订单", new BigDecimal("12.99"),
                LocalDateTime.of(2026, 10, 14, 22, 30));
        Map<String, String> parameters = new HashMap<>();
        for (String pair : orderInfo.split("&")) {
            String[] parts = pair.split("=", 2);
            parameters.put(parts[0], URLDecoder.decode(parts[1], StandardCharsets.UTF_8));
        }
        String signature = parameters.remove("sign");
        assertTrue(AlipaySignature.rsaCheck(AlipaySignature.getSignContent(parameters), signature,
                publicKey, "UTF-8", "RSA2"));
        assertEquals("alipay.trade.app.pay", parameters.get("method"));
        assertEquals(APP_ID, parameters.get("app_id"));
        assertEquals("https://example.test/api/payment/alipay/notify", parameters.get("notify_url"));
        String business = parameters.get("biz_content");
        assertTrue(business.contains("\"out_trade_no\":\"APP123\""));
        assertTrue(business.contains("\"total_amount\":\"12.99\""));
        assertTrue(business.contains("\"product_code\":\"QUICK_MSECURITY_PAY\""));
        assertTrue(business.contains("2026-10-14 22:30:00"));
    }

    @Test
    void verifiesRsa2SignatureAndExtractsPaidTradeWithoutContactingProvider() throws Exception {
        for (String status : new String[]{"TRADE_SUCCESS", "TRADE_FINISHED"}) {
            PaymentGateway.VerifiedNotice notice = gateway.verifyNotification("", signedNotice(status));

            assertEquals("ORDER123", notice.outTradeNo());
            assertEquals("ALIPAY123", notice.providerTransactionId());
            assertEquals(1299L, notice.amountFen());
            assertEquals("CNY", notice.currency());
            assertTrue(notice.paid(), status);
        }
    }

    @Test
    void rejectsAmountTamperedAfterSigning() throws Exception {
        Map<String, String> parameters = signedNotice("TRADE_SUCCESS");
        parameters.put("total_amount", "9999.00");

        SecurityException error = assertThrows(SecurityException.class,
                () -> gateway.verifyNotification("", parameters));

        assertEquals("Alipay notification signature is invalid", error.getMessage());
    }

    @Test
    void rejectsCorrectlySignedNotificationForAnotherApp() throws Exception {
        Map<String, String> parameters = notice("TRADE_SUCCESS");
        parameters.put("app_id", "another-app");
        sign(parameters);

        SecurityException error = assertThrows(SecurityException.class,
                () -> gateway.verifyNotification("", parameters));

        assertEquals("Alipay merchant identity mismatch", error.getMessage());
    }

    @Test
    void rejectsCorrectlySignedNotificationForAnotherSeller() throws Exception {
        Map<String, String> parameters = notice("TRADE_SUCCESS");
        parameters.put("seller_id", "another-seller");
        sign(parameters);

        SecurityException error = assertThrows(SecurityException.class,
                () -> gateway.verifyNotification("", parameters));

        assertEquals("Alipay merchant identity mismatch", error.getMessage());
    }

    @Test
    void doesNotTreatUnpaidOrClosedTradesAsSuccessfulPayments() throws Exception {
        for (String status : new String[]{"WAIT_BUYER_PAY", "TRADE_CLOSED", "UNKNOWN"}) {
            assertFalse(gateway.verifyNotification("", signedNotice(status)).paid(), status);
        }
    }

    @Test
    void rejectsCorrectlySignedAmountWithFractionalFen() throws Exception {
        Map<String, String> parameters = notice("TRADE_SUCCESS");
        parameters.put("total_amount", "12.999");
        sign(parameters);

        SecurityException error = assertThrows(SecurityException.class,
                () -> gateway.verifyNotification("", parameters));

        assertEquals("Alipay notification amount is invalid", error.getMessage());
    }

    private static Map<String, String> signedNotice(String status) throws AlipayApiException {
        Map<String, String> parameters = notice(status);
        sign(parameters);
        return parameters;
    }

    private static Map<String, String> notice(String status) {
        Map<String, String> parameters = new HashMap<>();
        parameters.put("app_id", APP_ID);
        parameters.put("seller_id", SELLER_ID);
        parameters.put("out_trade_no", "ORDER123");
        parameters.put("trade_no", "ALIPAY123");
        parameters.put("total_amount", "12.99");
        parameters.put("trade_status", status);
        return parameters;
    }

    private static void sign(Map<String, String> parameters) throws AlipayApiException {
        String signature = AlipaySignature.rsaSign(
                AlipaySignature.getSignContent(parameters), privateKey, "UTF-8", "RSA2");
        parameters.put("sign_type", "RSA2");
        parameters.put("sign", signature);
    }
}
