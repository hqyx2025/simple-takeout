package com.example.takeout.controller;

import com.example.takeout.service.thirdparty.ExternalPaymentService;
import com.example.takeout.service.thirdparty.PaymentChannels;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/payment")
public class PaymentNotificationController {

    private static final Logger log = LoggerFactory.getLogger(PaymentNotificationController.class);
    private static final String WECHAT_SUCCESS = "{\"code\":\"SUCCESS\",\"message\":\"成功\"}";

    private final ExternalPaymentService paymentService;

    public PaymentNotificationController(ExternalPaymentService paymentService) {
        this.paymentService = paymentService;
    }

    @PostMapping(value = "/wechat/notify", consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> wechatNotify(@RequestBody String rawBody, HttpServletRequest request) {
        Map<String, String> headers = new HashMap<>();
        for (String name : new String[]{"Wechatpay-Serial", "Wechatpay-Nonce", "Wechatpay-Signature", "Wechatpay-Timestamp"}) {
            headers.put(name, request.getHeader(name));
        }
        try {
            paymentService.acceptNotification(PaymentChannels.WECHAT, rawBody, headers);
            return ResponseEntity.ok(WECHAT_SUCCESS);
        } catch (com.example.takeout.common.BizException e) {
            return ResponseEntity.status(e.getCode() == 503 ? HttpStatus.SERVICE_UNAVAILABLE : HttpStatus.BAD_REQUEST)
                    .body("{\"code\":\"FAIL\",\"message\":\"通知未受理\"}");
        } catch (SecurityException e) {
            log.warn("Rejected WeChat Pay notification: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("{\"code\":\"FAIL\",\"message\":\"通知校验失败\"}");
        } catch (RuntimeException e) {
            log.error("WeChat Pay notification processing failed", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("{\"code\":\"FAIL\",\"message\":\"处理失败\"}");
        }
    }

    @PostMapping(value = "/alipay/notify", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE,
            produces = MediaType.TEXT_PLAIN_VALUE)
    public ResponseEntity<String> alipayNotify(@RequestParam Map<String, String> parameters) {
        try {
            paymentService.acceptNotification(PaymentChannels.ALIPAY, "", parameters);
            return ResponseEntity.ok("success");
        } catch (com.example.takeout.common.BizException e) {
            return ResponseEntity.status(e.getCode() == 503 ? HttpStatus.SERVICE_UNAVAILABLE : HttpStatus.BAD_REQUEST).body("failure");
        } catch (SecurityException e) {
            log.warn("Rejected Alipay notification: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("failure");
        } catch (RuntimeException e) {
            log.error("Alipay notification processing failed", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("failure");
        }
    }
}
