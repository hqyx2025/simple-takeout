package com.example.takeout.service.thirdparty;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

class HuaweiCloudSmsSenderTest {

    @Test
    void wssePasswordDigestUsesNonceCreatedAndAppSecret() {
        assertEquals("hn8RrOYzJrya/B9y1P1UD1hQTxw2D5TywKoixRRUBFM=",
                HuaweiCloudSmsSender.passwordDigest("nonce", "2026-01-02T03:04:05Z", "secret"));
        assertNotEquals("secret", HuaweiCloudSmsSender.passwordDigest("nonce", "created", "secret"));
    }
}
