package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.PushTokenDao;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class PushTokenServiceTest {
    private static final String TOKEN = "MAMzLg-test-device-token-that-is-long-enough";

    @Test
    void storesOnlyHashAndEncryptedTokenAndUnregistersWithinAccount() {
        PushTokenDao dao = mock(PushTokenDao.class);
        PushTokenCrypto crypto = new PushTokenCrypto("test-secret-that-is-at-least-32-characters");
        PushTokenService service = new PushTokenService(dao, crypto);
        service.register(7, TOKEN);
        ArgumentCaptor<String> hash = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<String> encrypted = ArgumentCaptor.forClass(String.class);
        verify(dao).register(eq(7L), hash.capture(), encrypted.capture(), anyLong());
        assertTrue(hash.getValue().matches("[0-9a-f]{64}"));
        assertFalse(encrypted.getValue().contains(TOKEN));
        assertEquals(TOKEN, crypto.decrypt(encrypted.getValue()));
        when(dao.findEncryptedByUserId(7)).thenReturn(List.of(encrypted.getValue()));
        assertEquals(List.of(TOKEN), service.tokensForUser(7));
        service.unregister(7, TOKEN);
        verify(dao).unregister(7, hash.getValue());
        assertNotEquals(service.profileId(7), service.profileId(8));
    }

    @Test
    void rejectsInvalidTokenAndTamperedCiphertext() {
        PushTokenDao dao = mock(PushTokenDao.class);
        PushTokenCrypto crypto = new PushTokenCrypto("test-secret-that-is-at-least-32-characters");
        PushTokenService service = new PushTokenService(dao, crypto);
        assertThrows(BizException.class, () -> service.register(7, "short"));
        assertThrows(BizException.class, () -> crypto.decrypt("v1:invalid"));
        verifyNoInteractions(dao);
    }

    @Test
    void refusesToStoreTokenWithoutStableServerEncryptionKey() {
        PushTokenDao dao = mock(PushTokenDao.class);
        PushTokenService service = new PushTokenService(dao, new PushTokenCrypto(""));
        assertThrows(BizException.class, () -> service.register(7, TOKEN));
        verifyNoInteractions(dao);
    }
}
