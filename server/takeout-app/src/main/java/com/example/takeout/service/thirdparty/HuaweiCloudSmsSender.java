package com.example.takeout.service.thirdparty;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.example.takeout.common.BizException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.HexFormat;

/** Huawei Cloud SMS REST adapter using its AppKey/WSSE authentication protocol. */
@Service
@ConditionalOnProperty(name = "takeout.sms.provider", havingValue = "huawei")
public class HuaweiCloudSmsSender implements SmsSender {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final DateTimeFormatter CREATED = DateTimeFormatter
            .ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC);

    private final URI endpoint;
    private final String appKey;
    private final String appSecret;
    private final String sender;
    private final String signature;
    private final String templateId;
    private final String countryCode;
    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;

    public HuaweiCloudSmsSender(
            @Value("${takeout.sms.huawei.endpoint:}") String endpoint,
            @Value("${takeout.sms.huawei.app-key:}") String appKey,
            @Value("${takeout.sms.huawei.app-secret:}") String appSecret,
            @Value("${takeout.sms.huawei.sender:}") String sender,
            @Value("${takeout.sms.huawei.signature:}") String signature,
            @Value("${takeout.sms.huawei.template-id:}") String templateId,
            @Value("${takeout.sms.huawei.country-code:86}") String countryCode,
            ObjectMapper objectMapper) {
        try {
            URI parsedEndpoint = URI.create(endpoint);
            if (!"https".equalsIgnoreCase(parsedEndpoint.getScheme()) || parsedEndpoint.getHost() == null
                    || blank(appKey) || blank(appSecret) || blank(sender) || blank(templateId)
                    || blank(countryCode)) {
                throw new IllegalStateException("Huawei Cloud SMS configuration is incomplete");
            }
            this.endpoint = URI.create(parsedEndpoint.toString().replaceAll("/$", "") + "/sms/batchSendSms/v1");
        } catch (IllegalArgumentException e) {
            throw new IllegalStateException("Huawei Cloud SMS endpoint is invalid");
        }
        this.appKey = appKey;
        this.appSecret = appSecret;
        this.sender = sender;
        this.signature = signature;
        this.templateId = templateId;
        this.countryCode = countryCode;
        this.objectMapper = objectMapper;
        this.httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    }

    @Override
    public void sendSmsCode(String phone, String code) {
        if (phone == null || !phone.matches("1\\d{10}") || code == null || !code.matches("\\d{6}")) {
            throw new BizException("验证码发送失败，请稍后重试");
        }
        String nonce = nonce();
        String created = CREATED.format(Instant.now());
        String digest = passwordDigest(nonce, created, appSecret);
        String parameters;
        try {
            parameters = objectMapper.writeValueAsString(java.util.List.of(code));
        } catch (IOException e) {
            throw new BizException("验证码发送失败，请稍后重试");
        }
        String body = form("from", sender) + "&" + form("to", "+" + countryCode + phone)
                + "&" + form("templateId", templateId) + "&" + form("templateParas", parameters);
        if (!blank(signature)) body += "&" + form("signature", signature);
        HttpRequest request = HttpRequest.newBuilder(endpoint)
                .timeout(Duration.ofSeconds(10))
                .header("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8")
                .header("Authorization", "WSSE realm=\"SDP\",profile=\"UsernameToken\",type=\"Appkey\"")
                .header("X-WSSE", "UsernameToken Username=\"" + appKey + "\", PasswordDigest=\""
                        + digest + "\", Nonce=\"" + nonce + "\", Created=\"" + created + "\"")
                .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8))
                .build();
        try {
            HttpResponse<String> response = httpClient.send(request,
                    HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() < 200 || response.statusCode() >= 300 || !accepted(response.body())) {
                throw new BizException("验证码发送失败，请稍后重试");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new BizException("验证码发送失败，请稍后重试");
        } catch (IOException e) {
            throw new BizException("验证码发送失败，请稍后重试");
        }
    }

    static String passwordDigest(String nonce, String created, String appSecret) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256")
                    .digest((nonce + created + appSecret).getBytes(StandardCharsets.UTF_8));
            return Base64.getEncoder().encodeToString(hash);
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is unavailable");
        }
    }

    private boolean accepted(String body) {
        try {
            JsonNode response = objectMapper.readTree(body);
            if (!"000000".equals(response.path("code").asText())) return false;
            JsonNode results = response.path("result");
            if (!results.isArray() || results.isEmpty()) return false;
            for (JsonNode result : results) {
                if (!"000000".equals(result.path("status").asText())) return false;
            }
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    private static String nonce() {
        byte[] bytes = new byte[16];
        RANDOM.nextBytes(bytes);
        return HexFormat.of().formatHex(bytes);
    }

    private static String form(String key, String value) {
        return URLEncoder.encode(key, StandardCharsets.UTF_8) + "="
                + URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }
}
