package com.example.takeout.service;

import com.example.takeout.common.BizException;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class BankCardCryptoTest {
    private static final String NUMBER = "6225888888880123";

    @Test
    void randomizedCiphertextRoundTripsWithoutContainingCardNumber() {
        BankCardCrypto crypto = new BankCardCrypto("unit-test-only-server-secret");
        String first = crypto.encrypt(NUMBER);
        String second = crypto.encrypt(NUMBER);
        assertNotEquals(first, second);
        assertFalse(first.contains(NUMBER));
        assertEquals(NUMBER, crypto.decrypt(first));
    }

    @Test
    void missingLegacyCiphertextReturnsExplicitMessage() {
        BankCardCrypto crypto = new BankCardCrypto("unit-test-only-server-secret");
        for (String value : new String[]{null, "", " "}) {
            BizException error = assertThrows(BizException.class, () -> crypto.decrypt(value));
            assertEquals("该银行卡未录入完整卡号，请重新添加", error.getMessage());
        }
    }

    @Test
    void corruptedCiphertextOrDifferentKeyNeverReturnsPlaintext() {
        BankCardCrypto crypto = new BankCardCrypto("unit-test-only-server-secret");
        String stored = crypto.encrypt(NUMBER);
        assertThrows(BizException.class, () -> new BankCardCrypto("different-unit-test-secret").decrypt(stored));
        assertThrows(BizException.class, () -> crypto.decrypt("v1:not-base64"));
    }
}
