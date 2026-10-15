package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.service.thirdparty.SmsSender;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class SmsVerificationServiceTest {

    private static final String SIGNING_SECRET = "a-test-signing-secret-that-is-at-least-32-chars";

    @Test
    void mockCodeIsGeneratedAndStoredAsHmacBeforeSending() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.setIfAbsent(anyString(), eq("1"), eq(Duration.ofSeconds(60)))).thenReturn(true);
        SmsSender sender = mock(SmsSender.class);
        when(sender.exposesCodeForDevelopment()).thenReturn(true);
        SmsVerificationService service = new SmsVerificationService(redis, sender, SIGNING_SECRET, 300, 60);

        SmsVerificationService.IssueResult result = service.issue("13800138000");

        assertEquals(true, result.mock());
        org.junit.jupiter.api.Assertions.assertTrue(result.code().matches("\\d{6}"));
        verify(sender).sendSmsCode("13800138000", result.code());
        verify(values).set(anyString(), org.mockito.ArgumentMatchers.argThat(stored -> !stored.equals(result.code())),
                eq(Duration.ofSeconds(300)));
    }

    @Test
    void realSenderNeverGetsCodeEchoedByIssueResult() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.setIfAbsent(anyString(), eq("1"), any(Duration.class))).thenReturn(true);
        SmsSender sender = mock(SmsSender.class);
        SmsVerificationService service = new SmsVerificationService(redis, sender, SIGNING_SECRET, 300, 60);

        SmsVerificationService.IssueResult result = service.issue("13800138000");

        assertEquals("", result.code());
        assertEquals(false, result.mock());
        verify(sender).sendSmsCode(eq("13800138000"), anyString());
    }

    @Test
    void cooldownRejectsAnotherSmsWithoutCallingSender() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.setIfAbsent(anyString(), eq("1"), any(Duration.class))).thenReturn(false);
        SmsSender sender = mock(SmsSender.class);
        SmsVerificationService service = new SmsVerificationService(redis, sender, SIGNING_SECRET, 300, 60);

        assertThrows(BizException.class, () -> service.issue("13800138000"));
        verify(sender, never()).sendSmsCode(anyString(), anyString());
    }

    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void consumeUsesRedisAtomicScriptAndRejectsReplay() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(), any(List.class), anyString())).thenReturn(1L, 0L);
        SmsVerificationService service = new SmsVerificationService(redis, mock(SmsSender.class),
                SIGNING_SECRET, 300, 60);

        service.consume("13800138000", "463829");
        assertThrows(BizException.class, () -> service.consume("13800138000", "463829"));
        verify(redis, org.mockito.Mockito.times(2)).execute(any(), any(List.class), anyString());
    }
}
