package com.example.takeout.service.thirdparty;

import com.alipay.api.AlipayApiException;
import com.alipay.api.AlipayClient;
import com.alipay.api.DefaultAlipayClient;
import com.alipay.api.AlipayConfig;
import com.alipay.api.domain.AlipayTradePrecreateModel;
import com.alipay.api.domain.AlipayTradeAppPayModel;
import com.alipay.api.domain.AlipayTradeQueryModel;
import com.alipay.api.domain.AlipayTradeCloseModel;
import com.alipay.api.domain.AlipayTradeRefundModel;
import com.alipay.api.internal.util.AlipaySignature;
import com.alipay.api.internal.util.AlipayLogger;
import com.alipay.api.request.AlipayTradePrecreateRequest;
import com.alipay.api.request.AlipayTradeAppPayRequest;
import com.alipay.api.request.AlipayTradeQueryRequest;
import com.alipay.api.request.AlipayTradeCloseRequest;
import com.alipay.api.request.AlipayTradeRefundRequest;
import com.alipay.api.response.AlipayTradePrecreateResponse;
import com.alipay.api.response.AlipayTradeQueryResponse;
import com.alipay.api.response.AlipayTradeCloseResponse;
import com.alipay.api.response.AlipayTradeRefundResponse;
import com.example.takeout.config.PaymentProperties;
import org.springframework.stereotype.Component;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.math.BigDecimal;
import java.util.Map;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

@Component
public class AlipayGateway implements PaymentGateway {

    private static final Logger log = LoggerFactory.getLogger(AlipayGateway.class);

    private final PaymentProperties properties;
    private volatile AlipayClient client;

    public AlipayGateway(PaymentProperties properties) {
        // The SDK's default business logger includes signed request and response parameters.
        AlipayLogger.setNeedEnableLogger(false);
        this.properties = properties;
    }

    @Override
    public String channel() {
        return PaymentChannels.ALIPAY;
    }

    @Override
    public String createQrPayment(String outTradeNo, String description, BigDecimal amount, LocalDateTime expiresAt) {
        AlipayTradePrecreateRequest request = new AlipayTradePrecreateRequest();
        request.setNotifyUrl(properties.getAlipay().getNotifyUrl());
        AlipayTradePrecreateModel model = new AlipayTradePrecreateModel();
        model.setOutTradeNo(outTradeNo);
        model.setTotalAmount(amount.toPlainString());
        model.setSubject(description);
        model.setTimeExpire(expiresAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
        request.setBizModel(model);
        try {
            AlipayTradePrecreateResponse response = client().execute(request);
            if (!response.isSuccess() || response.getQrCode() == null || response.getQrCode().isBlank()) {
                log.warn("Alipay precreate rejected: code={} subCode={} subMsg={}",
                        response.getCode(), response.getSubCode(), response.getSubMsg());
                throw new IllegalStateException("Alipay precreate failed: " + response.getSubMsg());
            }
            return response.getQrCode();
        } catch (AlipayApiException e) {
            log.warn("Alipay precreate transport failed: errorType={}", e.getClass().getSimpleName());
            throw new IllegalStateException("Alipay precreate request failed", e);
        }
    }

    @Override
    public String createAppPayment(String outTradeNo, String description, BigDecimal amount, LocalDateTime expiresAt) {
        AlipayTradeAppPayRequest request = new AlipayTradeAppPayRequest();
        request.setNotifyUrl(properties.getAlipay().getNotifyUrl());
        AlipayTradeAppPayModel model = new AlipayTradeAppPayModel();
        model.setOutTradeNo(outTradeNo);
        model.setTotalAmount(amount.toPlainString());
        model.setSubject(description);
        model.setProductCode("QUICK_MSECURITY_PAY");
        model.setSellerId(properties.getAlipay().getSellerId());
        model.setTimeExpire(expiresAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
        request.setBizModel(model);
        try {
            // sdkExecute signs locally; no provider transaction or QR code is created here.
            String orderInfo = client().sdkExecute(request).getBody();
            if (orderInfo == null || orderInfo.isBlank()) throw new IllegalStateException("Alipay app order is empty");
            return orderInfo;
        } catch (AlipayApiException e) {
            throw new IllegalStateException("Alipay app order signing failed", e);
        }
    }

    @Override
    public VerifiedNotice verifyNotification(String body, Map<String, String> parameters) {
        try {
            PaymentProperties.Alipay settings = properties.getAlipay();
            if (!AlipaySignature.rsaCheckV1(parameters, settings.getPublicKey(), "UTF-8", "RSA2")) {
                throw new SecurityException("Alipay notification signature is invalid");
            }
            if (!settings.getAppId().equals(parameters.get("app_id"))
                    || !settings.getSellerId().equals(parameters.get("seller_id"))) {
                throw new SecurityException("Alipay merchant identity mismatch");
            }
            String status = parameters.get("trade_status");
            boolean paid = "TRADE_SUCCESS".equals(status) || "TRADE_FINISHED".equals(status);
            String total = parameters.get("total_amount");
            long amountFen = new BigDecimal(total).movePointRight(2).longValueExact();
            return new VerifiedNotice(parameters.get("out_trade_no"), parameters.get("trade_no"),
                    amountFen, "CNY", paid);
        } catch (AlipayApiException e) {
            throw new SecurityException("Alipay notification verification failed", e);
        } catch (NumberFormatException | ArithmeticException e) {
            throw new SecurityException("Alipay notification amount is invalid", e);
        }
    }

    @Override
    public QueryResult query(String outTradeNo) {
        AlipayTradeQueryModel model = new AlipayTradeQueryModel();
        model.setOutTradeNo(outTradeNo);
        AlipayTradeQueryRequest request = new AlipayTradeQueryRequest();
        request.setBizModel(model);
        try {
            AlipayTradeQueryResponse response = client().execute(request);
            if (!response.isSuccess()) {
                // A signed provider response that the trade never existed is safe to close locally.
                if ("ACQ.TRADE_NOT_EXIST".equals(response.getSubCode())) return new QueryResult(false, true, null);
                throw new IllegalStateException("Alipay query failed: " + response.getSubMsg());
            }
            if (!outTradeNo.equals(response.getOutTradeNo())) {
                throw new SecurityException("Alipay query returned a different trade");
            }
            boolean paid = "TRADE_SUCCESS".equals(response.getTradeStatus())
                    || "TRADE_FINISHED".equals(response.getTradeStatus());
            VerifiedNotice notice = new VerifiedNotice(response.getOutTradeNo(), response.getTradeNo(),
                    new BigDecimal(response.getTotalAmount()).movePointRight(2).longValueExact(), "CNY", paid);
            return new QueryResult(paid, "TRADE_CLOSED".equals(response.getTradeStatus()), notice);
        } catch (AlipayApiException e) {
            throw new IllegalStateException("Alipay query failed", e);
        }
    }

    @Override
    public void close(String outTradeNo) {
        AlipayTradeCloseModel model = new AlipayTradeCloseModel();
        model.setOutTradeNo(outTradeNo);
        AlipayTradeCloseRequest request = new AlipayTradeCloseRequest();
        request.setBizModel(model);
        try {
            AlipayTradeCloseResponse response = client().execute(request);
            if (!response.isSuccess() || !outTradeNo.equals(response.getOutTradeNo())) {
                throw new IllegalStateException("Alipay close failed: " + response.getSubMsg());
            }
        } catch (AlipayApiException e) {
            throw new IllegalStateException("Alipay close failed", e);
        }
    }

    @Override
    public void refund(String outTradeNo, String outRefundNo, BigDecimal amount) {
        AlipayTradeRefundModel model = new AlipayTradeRefundModel();
        model.setOutTradeNo(outTradeNo);
        model.setOutRequestNo(outRefundNo);
        model.setRefundAmount(amount.toPlainString());
        model.setRefundReason("订单退款");
        AlipayTradeRefundRequest request = new AlipayTradeRefundRequest();
        request.setBizModel(model);
        try {
            AlipayTradeRefundResponse response = client().execute(request);
            if (!response.isSuccess() || !outTradeNo.equals(response.getOutTradeNo())
                    || new BigDecimal(response.getRefundFee()).compareTo(amount) != 0) {
                throw new IllegalStateException("Alipay refund failed or amount mismatch");
            }
        } catch (AlipayApiException e) {
            throw new IllegalStateException("Alipay refund failed", e);
        }
    }

    private AlipayClient client() {
        AlipayClient current = client;
        if (current == null) {
            synchronized (this) {
                current = client;
                if (current == null) {
                    PaymentProperties.Alipay settings = properties.getAlipay();
                    AlipayConfig config = new AlipayConfig();
                    config.setServerUrl(settings.getGatewayUrl());
                    config.setAppId(settings.getAppId());
                    config.setPrivateKey(settings.getAppPrivateKey());
                    config.setFormat("json");
                    config.setCharset("UTF-8");
                    config.setSignType("RSA2");
                    config.setAlipayPublicKey(settings.getPublicKey());
                    try {
                        current = new DefaultAlipayClient(config);
                    } catch (AlipayApiException e) {
                        throw new IllegalStateException("Alipay SDK configuration is invalid", e);
                    }
                    client = current;
                }
            }
        }
        return current;
    }
}
