package com.example.takeout.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class PaymentPasswordUtilTest {
    @Test
    void eachHashUsesRandomSaltAndOnlyMatchingPinIsAccepted() {
        String first = PaymentPasswordUtil.hash("135790");
        String second = PaymentPasswordUtil.hash("135790");
        assertNotEquals(first, second);
        assertTrue(first.startsWith("pbkdf2:210000:"));
        assertTrue(PaymentPasswordUtil.matches("135790", first));
        assertFalse(PaymentPasswordUtil.matches("135791", first));
        assertFalse(first.contains("135790"));
    }

    @Test
    void malformedOrMissingStoredHashIsRejected() {
        for (String value : new String[]{null, "", "old-login-hash", "pbkdf2:1:AA==:AA==", "pbkdf2:nope:a:b"}) {
            assertFalse(PaymentPasswordUtil.matches("135790", value));
        }
        assertFalse(PaymentPasswordUtil.matches(null, PaymentPasswordUtil.hash("135790")));
    }
}
