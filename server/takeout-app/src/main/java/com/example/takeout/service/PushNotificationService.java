package com.example.takeout.service;

import com.example.takeout.service.mq.DomainEventPublisher;
import com.example.takeout.service.thirdparty.PushSender;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@ConditionalOnProperty(name = "takeout.push.enabled", havingValue = "true")
public class PushNotificationService {

    private final JdbcTemplate jdbc;
    private final PushTokenService tokens;
    private final PushSender sender;

    public PushNotificationService(JdbcTemplate jdbc, PushTokenService tokens, PushSender sender) {
        this.jdbc = jdbc;
        this.tokens = tokens;
        this.sender = sender;
    }

    public void notifyOrderEvent(String eventType, long orderId) {
        Recipient recipient = recipient(eventType, orderId);
        if (recipient == null) return;
        List<String> deviceTokens = tokens.tokensForUser(recipient.userId());
        for (String deviceToken : deviceTokens) {
            sender.send(deviceToken, tokens.profileId(recipient.userId()), recipient.title(), recipient.body());
        }
    }

    private Recipient recipient(String eventType, long orderId) {
        if (orderId <= 0) return null;
        return switch (eventType) {
            case DomainEventPublisher.ORDER_CREATED -> forMerchant(orderId, "收到新订单", "有一笔新订单等待处理");
            case DomainEventPublisher.ORDER_PAID -> forMerchant(orderId, "订单已支付", "有订单已完成支付");
            case DomainEventPublisher.ORDER_CANCELLED -> forMerchant(orderId, "订单已取消", "一笔订单已取消");
            case DomainEventPublisher.ORDER_REFUNDED -> forCustomer(orderId, "退款进度更新", "一笔订单的退款状态已更新");
            default -> null;
        };
    }

    private Recipient forMerchant(long orderId, String title, String body) {
        List<Long> owners = jdbc.query("SELECT s.owner_id FROM orders o JOIN stores s ON s.id = o.store_id "
                        + "WHERE o.id = ?", (rs, row) -> rs.getLong(1), orderId);
        return owners.isEmpty() ? null : new Recipient(owners.getFirst(), title, body);
    }

    private Recipient forCustomer(long orderId, String title, String body) {
        List<Long> users = jdbc.query("SELECT user_id FROM orders WHERE id = ?",
                (rs, row) -> rs.getLong(1), orderId);
        return users.isEmpty() ? null : new Recipient(users.getFirst(), title, body);
    }

    private record Recipient(long userId, String title, String body) { }
}
