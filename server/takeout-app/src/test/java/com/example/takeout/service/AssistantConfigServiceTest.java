package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AssistantConfigServiceTest {
    private static final String ENDPOINT = "https://8.8.8.8/v1/chat/completions";
    private static final String SECRET = "server-secret-for-encryption-tests";
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final AtomicReference<Row> row = new AtomicReference<>(new Row(0, "", "", ""));
    private final AssistantConfigService service = new AssistantConfigService(jdbc, SECRET);

    @BeforeEach
    void persistedRow() {
        when(jdbc.query(anyString(), org.mockito.ArgumentMatchers.<RowMapper<Object>>any())).thenAnswer(invocation -> {
            Row current = row.get();
            ResultSet rs = mock(ResultSet.class);
            when(rs.getInt("enabled")).thenReturn(current.enabled());
            when(rs.getString("endpoint")).thenReturn(current.endpoint());
            when(rs.getString("model")).thenReturn(current.model());
            when(rs.getString("api_key_encrypted")).thenReturn(current.encrypted());
            RowMapper<Object> mapper = invocation.getArgument(1);
            return List.of(mapper.mapRow(rs, 0));
        });
        when(jdbc.update(anyString(), any(Object[].class))).thenAnswer(invocation -> {
            Object[] values = (Object[]) invocation.getRawArguments()[1];
            row.set(new Row((Integer) values[0], (String) values[1], (String) values[2], (String) values[3]));
            return 1;
        });
    }

    @Test
    void keyIsEncryptedAtRestAndNeverReturnedToAdminOrLogs() throws Exception {
        String key = "sk-confidential-key";
        var saved = service.save(request(true, key, false));

        assertTrue(saved.hasApiKey());
        assertTrue(row.get().encrypted().startsWith("v1:"));
        assertFalse(row.get().encrypted().contains(key));
        assertEquals(key, new AssistantConfigService(jdbc, SECRET).load().apiKey());
        ObjectMapper mapper = new ObjectMapper();
        assertFalse(mapper.writeValueAsString(saved).contains(key));
        assertFalse(mapper.writeValueAsString(service.load()).contains(key));
        assertFalse(mapper.writeValueAsString(request(true, key, false)).contains(key));
        assertFalse(service.load().toString().contains(key));
        assertFalse(request(true, key, false).toString().contains(key));

        String firstCiphertext = row.get().encrypted();
        service.save(request(true, key, false));
        assertNotEquals(firstCiphertext, row.get().encrypted());
    }

    @Test
    void emptyKeyPreservesStoredSecretAndExplicitClearRemovesIt() {
        service.save(request(true, "sk-existing", false));
        String encrypted = row.get().encrypted();
        assertTrue(service.save(request(true, " ", false)).hasApiKey());
        assertEquals(encrypted, row.get().encrypted());
        assertEquals("sk-existing", service.load().apiKey());

        assertFalse(service.save(request(false, "", true)).hasApiKey());
        assertEquals("", row.get().encrypted());
        assertEquals("", service.load().apiKey());
    }

    @Test
    void cannotEnableIncompleteConfigOrClearAnEnabledKey() {
        assertThrows(BizException.class, () -> service.save(request(true, "", false)));
        assertThrows(BizException.class, () -> service.save(
                new AssistantConfigService.SaveRequest(true, "", "model", "sk-new", false)));
        assertThrows(BizException.class, () -> service.save(
                new AssistantConfigService.SaveRequest(true, ENDPOINT, "", "sk-new", false)));
        service.save(request(true, "sk-existing", false));
        assertThrows(BizException.class, () -> service.save(request(true, "", true)));
        assertEquals("sk-existing", service.load().apiKey());
        assertThrows(BizException.class, () -> service.save(request(false, "sk-conflicting", true)));
    }

    @Test
    void malformedInputIsRejectedWithoutEchoingCredentials() {
        assertThrows(BizException.class, () -> service.save(null));
        assertThrows(BizException.class, () -> service.save(
                new AssistantConfigService.SaveRequest(null, "", "", "", false)));
        assertThrows(BizException.class, () -> service.save(
                new AssistantConfigService.SaveRequest(false, "", "m".repeat(129), "", false)));
        BizException error = assertThrows(BizException.class,
                () -> service.save(request(false, "sk-private\r\nInjected:header", false)));
        assertFalse(error.getMessage().contains("sk-private"));
        assertThrows(BizException.class, () -> service.save(request(false, "k".repeat(4097), false)));
    }

    @Test
    void endpointsMustBePublicHttpsChatCompletionsWithoutEmbeddedCredentials() {
        for (String endpoint : List.of(
                "http://8.8.8.8/v1/chat/completions", "https://8.8.8.8/v1/models",
                "https://secret@8.8.8.8/v1/chat/completions", "https://8.8.8.8/v1/chat/completions?apiKey=secret",
                "https://8.8.8.8/v1/chat/completions#secret", "https://8.8.8.8:8087/v1/chat/completions",
                "https://localhost/v1/chat/completions", "https://127.0.0.1/v1/chat/completions",
                "https://10.0.0.1/v1/chat/completions", "https://172.16.0.1/v1/chat/completions",
                "https://192.168.1.1/v1/chat/completions", "https://169.254.169.254/v1/chat/completions",
                "https://168.63.129.16/v1/chat/completions",
                "https://100.64.0.1/v1/chat/completions", "https://[::1]/v1/chat/completions",
                "https://[fd00::1]/v1/chat/completions", "https://[::ffff:127.0.0.1]/v1/chat/completions")) {
            assertThrows(BizException.class, () -> AssistantConfigService.validateEndpoint(endpoint), endpoint);
        }
        assertEquals(ENDPOINT, AssistantConfigService.validateEndpoint(ENDPOINT).toString());
    }

    @Test
    void corruptOrChangedEncryptionKeyFailsSafelyAndCanBeReplaced() {
        service.save(request(true, "sk-sensitive", false));
        AssistantConfigService changedSecret = new AssistantConfigService(jdbc, "new-server-secret");
        BizException changed = assertThrows(BizException.class, changedSecret::load);
        assertEquals(503, changed.getCode());
        assertFalse(changed.getMessage().contains("sk-sensitive"));
        assertTrue(changedSecret.view().hasApiKey());
        changedSecret.save(request(true, "sk-replaced", false));
        assertEquals("sk-replaced", changedSecret.load().apiKey());

        row.set(new Row(1, ENDPOINT, "model", "v1:invalid"));
        assertThrows(BizException.class, changedSecret::load);
        assertFalse(changedSecret.save(request(false, "", true)).hasApiKey());
    }

    private AssistantConfigService.SaveRequest request(boolean enabled, String key, boolean clear) {
        return new AssistantConfigService.SaveRequest(enabled, ENDPOINT, "model", key, clear);
    }

    private record Row(int enabled, String endpoint, String model, String encrypted) { }
}
