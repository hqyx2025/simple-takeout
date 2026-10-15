package com.example.takeout.service.thirdparty;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.example.takeout.service.PushTokenCrypto;
import io.jsonwebtoken.Jwts;
import org.junit.jupiter.api.Test;

import java.security.KeyPairGenerator;
import java.util.Base64;

import static org.junit.jupiter.api.Assertions.*;

class HuaweiPushKitSenderTest {
    @Test
    void enabledAdapterRequiresAgcServiceAccount() {
        assertThrows(IllegalStateException.class,
                () -> new HuaweiPushKitSender("", "", "", "", new ObjectMapper(),
                        new PushTokenCrypto("test-key-stable-at-least-32-characters")));
    }

    @Test
    void signsV3ServiceAccountJwtWithPs256AndOneHourExpiry() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        var keyPair = generator.generateKeyPair();
        String pem = "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getEncoder().encodeToString(keyPair.getPrivate().getEncoded())
                + "\n-----END PRIVATE KEY-----";
        HuaweiPushKitSender sender = new HuaweiPushKitSender("project-1", "key-1", "sub-account", pem,
                new ObjectMapper(), new PushTokenCrypto("test-key-stable-at-least-32-characters"));
        String token = sender.authToken();
        var jwt = Jwts.parser().verifyWith(keyPair.getPublic()).build().parseSignedClaims(token);
        assertEquals("PS256", jwt.getHeader().getAlgorithm());
        assertEquals("key-1", jwt.getHeader().getKeyId());
        assertEquals("sub-account", jwt.getPayload().getIssuer());
        assertTrue(jwt.getPayload().getAudience().contains("https://oauth-login.cloud.huawei.com/oauth2/v3/token"));
        assertEquals(3600000, jwt.getPayload().getExpiration().getTime() - jwt.getPayload().getIssuedAt().getTime());
        assertEquals(token, sender.authToken());
    }
}
