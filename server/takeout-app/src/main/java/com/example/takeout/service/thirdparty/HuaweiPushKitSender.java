package com.example.takeout.service.thirdparty;

import com.example.takeout.common.BizException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.example.takeout.service.PushTokenService;
import com.example.takeout.service.PushTokenCrypto;
import io.jsonwebtoken.Jwts;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.List;
import java.util.Map;

/** Huawei Push Kit V3 REST transport. Credentials are AGC service-account values, env-only. */
@Service
@ConditionalOnProperty(name = "takeout.push.enabled", havingValue = "true")
public class HuaweiPushKitSender implements PushSender {

    private final String keyId;
    private final String subAccount;
    private final PrivateKey privateKey;
    private final URI sendUri;
    private final ObjectMapper mapper;
    private volatile HttpClient client;
    private volatile CachedJwt cachedJwt;

    public HuaweiPushKitSender(@Value("${takeout.push.huawei.project-id:}") String projectId,
                               @Value("${takeout.push.huawei.key-id:}") String keyId,
                               @Value("${takeout.push.huawei.sub-account:}") String subAccount,
                               @Value("${takeout.push.huawei.private-key:}") String privateKeyPem,
                               ObjectMapper mapper, PushTokenCrypto tokenCrypto) {
        if (blank(projectId) || !projectId.matches("[A-Za-z0-9._-]{1,128}")
                || blank(keyId) || blank(subAccount) || blank(privateKeyPem)) {
            throw new IllegalStateException("Huawei Push Kit is enabled but AGC service-account credentials are incomplete");
        }
        tokenCrypto.requireKey();
        this.keyId = keyId;
        this.subAccount = subAccount;
        this.privateKey = parsePrivateKey(privateKeyPem);
        this.sendUri = URI.create("https://push-api.cloud.huawei.com/v3/" + projectId + "/messages:send");
        this.mapper = mapper;
    }

    @Override
    public void send(String deviceToken, String profileId, String title, String body) {
        PushTokenService.validate(deviceToken);
        Map<String, Object> notification = Map.of(
                "category", "EXPRESS",
                "title", messageText(title, 64),
                "body", messageText(body, 256),
                "profileId", messageText(profileId, 64),
                "clickAction", Map.of("actionType", 0),
                "notifyId", (int) (System.currentTimeMillis() & 0x7fffffff));
        Map<String, Object> payload = Map.of(
                "payload", Map.of("notification", notification),
                "target", Map.of("token", List.of(deviceToken)),
                "pushOptions", Map.of("testMessage", false));
        try {
            HttpRequest request = HttpRequest.newBuilder(sendUri)
                    .timeout(Duration.ofSeconds(10))
                    .header("Authorization", "Bearer " + authToken())
                    .header("Content-Type", "application/json")
                    .header("push-type", "0")
                    .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(payload), StandardCharsets.UTF_8))
                    .build();
            HttpResponse<String> response = httpClient().send(request,
                    HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() < 200 || response.statusCode() >= 300
                    || !"80000000".equals(mapper.readTree(response.body()).path("code").asText())) {
                throw unavailable();
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw unavailable();
        } catch (IOException | RuntimeException e) {
            if (e instanceof BizException biz) throw biz;
            throw unavailable();
        }
    }

    String authToken() {
        CachedJwt current = cachedJwt;
        if (current != null && current.expiresAtMillis() > System.currentTimeMillis()) return current.value();
        synchronized (this) {
            current = cachedJwt;
            if (current != null && current.expiresAtMillis() > System.currentTimeMillis()) return current.value();
            long issuedAt = Instant.now().getEpochSecond();
            long expiry = issuedAt + 3600;
            String token = Jwts.builder().header().keyId(keyId).type("JWT").and()
                    .issuer(subAccount)
                    .audience().add("https://oauth-login.cloud.huawei.com/oauth2/v3/token").and()
                    .issuedAt(java.util.Date.from(Instant.ofEpochSecond(issuedAt)))
                    .expiration(java.util.Date.from(Instant.ofEpochSecond(expiry)))
                    .signWith(privateKey, Jwts.SIG.PS256)
                    .compact();
            cachedJwt = new CachedJwt(token, (expiry - 60) * 1000);
            return token;
        }
    }

    private HttpClient httpClient() {
        if (client == null) {
            synchronized (this) {
                if (client == null) client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
            }
        }
        return client;
    }

    private static PrivateKey parsePrivateKey(String pem) {
        try {
            String encoded = pem.replace("\\n", "").replace("-----BEGIN PRIVATE KEY-----", "")
                    .replace("-----END PRIVATE KEY-----", "").replaceAll("\\s", "");
            return KeyFactory.getInstance("RSA").generatePrivate(
                    new PKCS8EncodedKeySpec(Base64.getDecoder().decode(encoded)));
        } catch (Exception e) {
            throw new IllegalStateException("Huawei Push Kit service-account private key is invalid");
        }
    }

    private static String messageText(String value, int maxLength) {
        if (blank(value) || value.length() > maxLength || value.chars().anyMatch(Character::isISOControl)) {
            throw new BizException("推送内容无效");
        }
        return value;
    }

    private static BizException unavailable() {
        return new BizException(503, "推送服务暂不可用");
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }

    private record CachedJwt(String value, long expiresAtMillis) { }
}
