package com.example.takeout.service.thirdparty;

import com.example.takeout.config.PaymentProperties;
import com.wechat.pay.java.core.exception.ValidationException;
import com.wechat.pay.java.core.exception.ServiceException;
import com.wechat.pay.java.core.RSAAutoCertificateConfig;
import com.wechat.pay.java.core.notification.NotificationParser;
import com.wechat.pay.java.core.notification.RequestParam;
import com.wechat.pay.java.service.payments.nativepay.NativePayService;
import com.wechat.pay.java.service.payments.nativepay.model.Amount;
import com.wechat.pay.java.service.payments.nativepay.model.PrepayRequest;
import com.wechat.pay.java.service.payments.nativepay.model.PrepayResponse;
import com.wechat.pay.java.service.payments.nativepay.model.QueryOrderByOutTradeNoRequest;
import com.wechat.pay.java.service.payments.nativepay.model.CloseOrderRequest;
import com.wechat.pay.java.service.payments.model.Transaction;
import com.wechat.pay.java.service.refund.RefundService;
import com.wechat.pay.java.service.refund.model.CreateRequest;
import com.wechat.pay.java.service.refund.model.AmountReq;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.Map;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

@Component
public class WechatPayGateway implements PaymentGateway {

    private final PaymentProperties properties;
    private volatile RSAAutoCertificateConfig config;

    public WechatPayGateway(PaymentProperties properties) {
        this.properties = properties;
    }

    @Override
    public String channel() {
        return PaymentChannels.WECHAT;
    }

    @Override
    public String createQrPayment(String outTradeNo, String description, BigDecimal amount, LocalDateTime expiresAt) {
        PaymentProperties.Wechat settings = properties.getWechat();
        PrepayRequest request = new PrepayRequest();
        request.setAppid(settings.getAppId());
        request.setMchid(settings.getMchId());
        request.setDescription(description);
        request.setOutTradeNo(outTradeNo);
        request.setNotifyUrl(settings.getNotifyUrl());
        request.setTimeExpire(expiresAt.atZone(ZoneId.of("Asia/Shanghai")).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME));
        Amount total = new Amount();
        total.setTotal(amount.movePointRight(2).intValueExact());
        total.setCurrency("CNY");
        request.setAmount(total);
        PrepayResponse response = new NativePayService.Builder().config(config()).build().prepay(request);
        if (response.getCodeUrl() == null || response.getCodeUrl().isBlank()) {
            throw new IllegalStateException("WeChat Pay did not return a payment URL");
        }
        return response.getCodeUrl();
    }

    @Override
    public VerifiedNotice verifyNotification(String body, Map<String, String> headers) {
        RequestParam request = new RequestParam.Builder()
                .serialNumber(required(headers, "Wechatpay-Serial"))
                .nonce(required(headers, "Wechatpay-Nonce"))
                .signature(required(headers, "Wechatpay-Signature"))
                .timestamp(required(headers, "Wechatpay-Timestamp"))
                .body(body)
                .build();
        Transaction transaction;
        try {
            transaction = new NotificationParser(config()).parse(request, Transaction.class);
        } catch (ValidationException e) {
            throw new SecurityException("WeChat Pay notification signature is invalid", e);
        }
        return verified(transaction);
    }

    @Override
    public QueryResult query(String outTradeNo) {
        QueryOrderByOutTradeNoRequest request = new QueryOrderByOutTradeNoRequest();
        request.setMchid(properties.getWechat().getMchId());
        request.setOutTradeNo(outTradeNo);
        Transaction transaction;
        try {
            transaction = new NativePayService.Builder().config(config()).build().queryOrderByOutTradeNo(request);
        } catch (ServiceException e) {
            if ("ORDER_NOT_EXIST".equals(e.getErrorCode())) return new QueryResult(false, true, null);
            throw e;
        }
        VerifiedNotice notice = verified(transaction);
        return new QueryResult(notice.paid(), transaction.getTradeState() == Transaction.TradeStateEnum.CLOSED
                || transaction.getTradeState() == Transaction.TradeStateEnum.REVOKED, notice);
    }

    @Override
    public void close(String outTradeNo) {
        CloseOrderRequest request = new CloseOrderRequest();
        request.setMchid(properties.getWechat().getMchId());
        request.setOutTradeNo(outTradeNo);
        new NativePayService.Builder().config(config()).build().closeOrder(request);
    }

    @Override
    public void refund(String outTradeNo, String outRefundNo, BigDecimal amount) {
        refund(outTradeNo, outRefundNo, amount, amount);
    }

    @Override
    public void refund(String outTradeNo, String outRefundNo, BigDecimal amount, BigDecimal originalAmount) {
        CreateRequest request = new CreateRequest();
        request.setOutTradeNo(outTradeNo);
        request.setOutRefundNo(outRefundNo);
        request.setReason("订单退款");
        AmountReq refundAmount = new AmountReq();
        refundAmount.setTotal(originalAmount.movePointRight(2).longValueExact());
        refundAmount.setRefund(amount.movePointRight(2).longValueExact());
        refundAmount.setCurrency("CNY");
        request.setAmount(refundAmount);
        com.wechat.pay.java.service.refund.model.Refund response =
                new RefundService.Builder().config(config()).build().create(request);
        if (!outRefundNo.equals(response.getOutRefundNo())) {
            throw new SecurityException("WeChat Pay refund response mismatch");
        }
        if (!"SUCCESS".equals(String.valueOf(response.getStatus()))) {
            throw new IllegalStateException("WeChat Pay refund is still pending; retry with the same refund number");
        }
    }

    private VerifiedNotice verified(Transaction transaction) {
        PaymentProperties.Wechat settings = properties.getWechat();
        if (!settings.getMchId().equals(transaction.getMchid())
                || !settings.getAppId().equals(transaction.getAppid())) {
            throw new SecurityException("WeChat Pay merchant identity mismatch");
        }
        if (transaction.getAmount() == null || transaction.getAmount().getTotal() == null) {
            throw new SecurityException("WeChat Pay notification has no total amount");
        }
        return new VerifiedNotice(transaction.getOutTradeNo(), transaction.getTransactionId(),
                transaction.getAmount().getTotal(), transaction.getAmount().getCurrency(),
                transaction.getTradeState() == Transaction.TradeStateEnum.SUCCESS);
    }

    private RSAAutoCertificateConfig config() {
        RSAAutoCertificateConfig current = config;
        if (current == null) {
            synchronized (this) {
                current = config;
                if (current == null) {
                    PaymentProperties.Wechat settings = properties.getWechat();
                    current = new RSAAutoCertificateConfig.Builder()
                            .merchantId(settings.getMchId())
                            .privateKeyFromPath(settings.getPrivateKeyPath())
                            .merchantSerialNumber(settings.getMerchantSerialNumber())
                            .apiV3Key(settings.getApiV3Key())
                            .build();
                    config = current;
                }
            }
        }
        return current;
    }

    private static String required(Map<String, String> headers, String name) {
        String value = headers.get(name);
        if (value == null || value.isBlank()) throw new SecurityException("Missing WeChat Pay signature header");
        return value;
    }
}
