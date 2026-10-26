package com.example.takeout.service;

import com.example.takeout.service.mq.DomainEventPublisher;
import com.example.takeout.service.thirdparty.PushSender;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class PushNotificationServiceTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final PushTokenService tokens = mock(PushTokenService.class);
    private final PushSender sender = mock(PushSender.class);
    private final PushNotificationService service = new PushNotificationService(jdbc, tokens, sender);

    @Test
    @SuppressWarnings("unchecked")
    void merchantRejectionNotifiesCustomerUsingTrustedReasonInsteadOfFreeformNote() throws Exception {
        when(jdbc.query(anyString(), any(RowMapper.class), eq(71L))).thenAnswer(invocation -> {
            String sql = invocation.getArgument(0);
            assertFalse(sql.contains("reject_note"));
            RowMapper<Object> mapper = invocation.getArgument(1);
            ResultSet rs = mock(ResultSet.class);
            when(rs.getLong("user_id")).thenReturn(1L);
            when(rs.getLong("owner_id")).thenReturn(99L);
            when(rs.getString("cancel_source")).thenReturn("MERCHANT");
            when(rs.getString("cancel_reason")).thenReturn("「招牌饭(大份)」暂时缺货");
            when(rs.getString("pay_time")).thenReturn("2026-10-26 12:01:00");
            return List.of(mapper.mapRow(rs, 0));
        });
        when(tokens.tokensForUser(1)).thenReturn(List.of("customer-device"));
        when(tokens.profileId(1)).thenReturn("customer-profile");

        service.notifyOrderEvent(DomainEventPublisher.ORDER_CANCELLED, 71);

        verify(tokens).tokensForUser(1);
        verify(tokens, never()).tokensForUser(99);
        verify(sender).send("customer-device", "customer-profile", "商家未能接单",
                "「招牌饭(大份)」暂时缺货，已按原支付渠道退款");
    }

    @Test
    @SuppressWarnings("unchecked")
    void customerCancellationStillNotifiesMerchant() throws Exception {
        when(jdbc.query(anyString(), any(RowMapper.class), eq(72L))).thenAnswer(invocation -> {
            RowMapper<Object> mapper = invocation.getArgument(1);
            ResultSet rs = mock(ResultSet.class);
            when(rs.getLong("user_id")).thenReturn(1L);
            when(rs.getLong("owner_id")).thenReturn(99L);
            when(rs.getString("cancel_source")).thenReturn("USER");
            when(rs.getString("cancel_reason")).thenReturn("用户取消订单");
            when(rs.getString("pay_time")).thenReturn("2026-10-26 12:01:00");
            return List.of(mapper.mapRow(rs, 0));
        });
        when(tokens.tokensForUser(99)).thenReturn(List.of("merchant-device"));
        when(tokens.profileId(99)).thenReturn("merchant-profile");

        service.notifyOrderEvent(DomainEventPublisher.ORDER_CANCELLED, 72);

        verify(sender).send("merchant-device", "merchant-profile", "订单已取消", "用户取消订单");
        verify(tokens, never()).tokensForUser(1);
    }
}
