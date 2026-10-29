package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.service.thirdparty.SmsSender;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class SmsVerificationServiceTest {

    @Test void quotaAliasesAreCanonicalButDistinctOrdinaryMailboxesStayDistinct() {
        assertEquals("firstlast@gmail.com", SmsVerificationService.recipientBudgetIdentity("First.Last+tag@GoogleMail.com"));
        assertEquals("first.last@example.com", SmsVerificationService.recipientBudgetIdentity("first.last+tag@example.com"));
        assertNotEquals(SmsVerificationService.recipientBudgetIdentity("first.last@example.com"),
                SmsVerificationService.recipientBudgetIdentity("firstlast@example.com"));
    }

    private static final String SIGNING_SECRET = "a-test-signing-secret-that-is-at-least-32-chars";

    @Test
    void captchaIsAnExpiringImageAndCannotBeReusedOrMovedToAnotherSource() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(values);
        var service = new SmsVerificationService(redis, mock(SmsSender.class), SIGNING_SECRET, 300, 60);
        var image = service.issueCaptcha("source-a");
        org.junit.jupiter.api.Assertions.assertTrue(image.image().startsWith("data:image/png;base64,"));
        verify(values).set(eq("takeout:captcha:" + image.id()), anyString(), eq(Duration.ofMinutes(3)));
        String answer = "ABCDE";
        String digest;
        try {
            var mac = javax.crypto.Mac.getInstance("HmacSHA256");
            mac.init(new javax.crypto.spec.SecretKeySpec(SIGNING_SECRET.getBytes(java.nio.charset.StandardCharsets.UTF_8), "HmacSHA256"));
            digest = java.util.HexFormat.of().formatHex(mac.doFinal(("source-a:" + answer).getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        } catch (java.security.GeneralSecurityException e) { throw new AssertionError(e); }
        when(redis.execute(org.mockito.ArgumentMatchers.<org.springframework.data.redis.core.script.DefaultRedisScript<String>>any(),
                eq(List.of("takeout:captcha:" + image.id())))).thenReturn(digest, (String) null);
        service.consumeCaptcha("source-a", image.id(), "abcde");
        assertThrows(BizException.class, () -> service.consumeCaptcha("source-a", image.id(), answer));
        when(redis.execute(org.mockito.ArgumentMatchers.<org.springframework.data.redis.core.script.DefaultRedisScript<String>>any(),
                eq(List.of("takeout:captcha:" + image.id())))).thenReturn(digest);
        assertThrows(BizException.class, () -> service.consumeCaptcha("source-b", image.id(), answer));
        assertThrows(BizException.class, () -> service.consumeCaptcha("source-a", null, answer));
    }

    @Test
    void hourlyBudgetsAreIsolatedByRecipient() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.setIfAbsent(anyString(), eq("1"), any(Duration.class))).thenReturn(true);
        when(values.increment(anyString())).thenReturn(1L);
        var service = new SmsVerificationService(redis, mock(SmsSender.class), SIGNING_SECRET, 300, 60);
        service.issue("first@example.com");
        service.issue("second@example.com");
        var keys = org.mockito.ArgumentCaptor.forClass(String.class);
        verify(values, org.mockito.Mockito.times(6)).increment(keys.capture());
        assertEquals(2, keys.getAllValues().stream().filter(k -> k.startsWith("takeout:verification:hourly:"))
                .distinct().count());
        assertEquals(1, keys.getAllValues().stream().filter(k -> k.startsWith("takeout:verification:global-hourly:"))
                .distinct().count());
    }

    @Test
    void springCreatesServiceWhenCompatibilityConstructorAlsoExists() {
        new ApplicationContextRunner()
                .withBean(StringRedisTemplate.class, () -> mock(StringRedisTemplate.class))
                .withBean(SmsSender.class, () -> mock(SmsSender.class))
                .withUserConfiguration(SmsVerificationService.class)
                .withPropertyValues("takeout.sms.hmac-secret=" + SIGNING_SECRET)
                .run(context -> {
                    assertNull(context.getStartupFailure());
                    assertNotNull(context.getBean(SmsVerificationService.class));
                });
    }

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
        verify(sender).sendVerificationCode("13800138000", result.code(), "13800138000");
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
        verify(sender).sendVerificationCode(eq("13800138000"), anyString(), eq("13800138000"));
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
        verify(sender, never()).sendVerificationCode(anyString(), anyString(), anyString());
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
