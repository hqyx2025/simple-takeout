package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.service.thirdparty.ObjectStorage;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class UploadDefenseTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final ObjectStorage storage = mock(ObjectStorage.class);
    private final LoginRateLimiter limiter = mock(LoginRateLimiter.class);
    private final UploadService service = new UploadService(jdbc, storage, limiter, 100, 1000);
    private MockMultipartFile image() {
        return new MockMultipartFile("file", "photo.jpg", "image/jpeg", new byte[]{(byte)255, (byte)216, (byte)255});
    }

    @Test void blockedAccountNeverWritesFilesOrQuota() {
        when(limiter.isBlocked("upload", "u7")).thenReturn(true);
        assertEquals(429, assertThrows(BizException.class, () -> service.store(7, image())).getCode());
        verifyNoInteractions(jdbc, storage);
    }

    @Test void exhaustedBudgetNeverWritesAnObject() {
        assertEquals(429, assertThrows(BizException.class, () -> service.store(7, image())).getCode());
        verifyNoInteractions(storage);
    }

    @Test void bothGlobalAndAccountReservationsAreRequiredBeforeStore() {
        when(jdbc.update(startsWith("UPDATE upload_usage"), any(Object[].class))).thenReturn(1);
        when(storage.store(any())).thenReturn("/uploads/example.jpg");
        assertEquals("/uploads/example.jpg", service.store(7, image()));
        var order = inOrder(jdbc, storage);
        order.verify(jdbc).update(startsWith("INSERT INTO upload_usage"), eq(0L));
        order.verify(jdbc).update(startsWith("UPDATE upload_usage"), eq(3L), eq(0L), eq(997L));
        order.verify(jdbc).update(startsWith("INSERT INTO upload_usage"), eq(7L));
        order.verify(jdbc).update(startsWith("UPDATE upload_usage"), eq(3L), eq(7L), eq(97L));
        order.verify(storage).store(any());
    }
}
