package com.example.takeout.service.mq;

import com.example.takeout.common.InstanceId;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.connection.stream.Consumer;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.data.redis.connection.stream.ReadOffset;
import org.springframework.data.redis.connection.stream.StreamOffset;
import org.springframework.data.redis.connection.stream.StreamReadOptions;
import org.springframework.data.redis.connection.stream.StreamRecords;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.List;
import java.util.Map;

/**
 * 领域事件消费者：从 Redis Stream 读取事件并执行「可延迟」的下游动作。
 *
 * <p><b>消费组 + 幂等</b>：使用消费者组（consumer group）保证同一事件在同组内
 * 只被一个实例消费；读完即 ACK。由于中继是「至少一次」投递，
 * 这里用 Redis SETGET 式去重键（eventId）做幂等，重复事件直接跳过。</p>
 *
 * <p><b>为什么这些动作可以异步？</b>
 * 消费端只做通知类副作用（商户提醒、运营统计等），不参与订单金额、
 * 库存与状态机的写入，因此即使延迟或被重复消费也不影响业务正确性。</p>
 *
 * <p>Redis 不可用时消费者静默跳过，不影响主流程；事件仍安全保存在 outbox 表中。</p>
 */
@Component
public class DomainEventConsumer {

    private static final Logger log = LoggerFactory.getLogger(DomainEventConsumer.class);

    private static final String GROUP = "takeout-consumers";

    /**
     * 消费者名必须「每实例不同」。
     *
     * <p>Redis Stream 消费组按消费者名区分成员：所有实例都叫 {@code consumer-1} 时，
     * 消费组会把它们当成<b>同一个消费者</b>——消息在实例间互相抢占，实例各自还没法
     * 追踪自己的未 ACK 消息（PENDING 列表混在一起）。带上实例标识后每个实例是独立成员。</p>
     */
    private final String consumerName = "consumer-" + InstanceId.current();

    /** 幂等去重键前缀。 */
    private static final String DEDUP_PREFIX = "takeout:event:consumed:";

    private final ObjectProvider<StringRedisTemplate> redisProvider;

    @Value("${takeout.mq.enabled:true}")
    private boolean enabled = true;

    @Value("${takeout.mq.consumer-batch:20}")
    private int batchSize = 20;

    /** 幂等去重键保留时长（小时）。 */
    @Value("${takeout.mq.dedup-hours:24}")
    private int dedupHours = 24;

    public DomainEventConsumer(ObjectProvider<StringRedisTemplate> redisProvider) {
        this.redisProvider = redisProvider;
    }

    @Scheduled(fixedDelayString = "${takeout.mq.consumer-scan-ms:2000}",
            initialDelayString = "${takeout.mq.consumer-initial-ms:15000}")
    public void consume() {
        if (!enabled) {
            return;
        }
        StringRedisTemplate redis = redisProvider.getIfAvailable();
        if (redis == null) {
            return;
        }
        try {
            ensureGroup(redis);
            List<MapRecord<String, Object, Object>> records = redis.opsForStream().read(
                    Consumer.from(GROUP, consumerName),
                    StreamReadOptions.empty().count(batchSize),
                    StreamOffset.create(DomainEventPublisher.STREAM_KEY, ReadOffset.lastConsumed()));
            if (records == null || records.isEmpty()) {
                return;
            }
            for (MapRecord<String, Object, Object> record : records) {
                try {
                    if (handle(redis, record)) {
                        redis.opsForStream().acknowledge(DomainEventPublisher.STREAM_KEY, GROUP, record.getId());
                    }
                } catch (Exception e) {
                    // 单条处理失败不 ACK，留待下次重读；不阻塞其余事件
                    log.warn("[事件消费] 处理失败 id={}", record.getId(), e);
                }
            }
        } catch (Exception e) {
            log.warn("[事件消费] 读取失败（将在下一轮重试）", e);
        }
    }

    /**
     * 确保 Stream 与消费者组存在。
     *
     * <p>Stream 只有在第一条消息写入后才存在，因此这里先按需创建空 Stream
     * （XADD 一条占位会被立即裁掉，更简单的做法是用 XGROUP CREATE 的 MKSTREAM 语义：
     * 在 key 不存在时直接创建组即可让 Stream 同时建立）。
     * 否则消费者在首条事件到来前每轮都会拿到 NOGROUP 并刷警告日志。</p>
     */
    private void ensureGroup(StringRedisTemplate redis) {
        try {
            if (Boolean.TRUE.equals(redis.hasKey(DomainEventPublisher.STREAM_KEY))) {
                redis.opsForStream().createGroup(DomainEventPublisher.STREAM_KEY, ReadOffset.from("0"), GROUP);
                return;
            }
            // key 不存在：写入一条占位并立刻删除，使 Stream 建立后再建组
            MapRecord<String, String, String> placeholder = StreamRecords
                    .mapBacked(Map.of("bootstrap", "1"))
                    .withStreamKey(DomainEventPublisher.STREAM_KEY);
            org.springframework.data.redis.connection.stream.RecordId id =
                    redis.opsForStream().add(placeholder);
            redis.opsForStream().createGroup(DomainEventPublisher.STREAM_KEY, ReadOffset.from("0"), GROUP);
            if (id != null) {
                redis.opsForStream().delete(DomainEventPublisher.STREAM_KEY, id);
            }
            log.info("[事件消费] 已初始化 Stream 与消费组 stream={} group={}",
                    DomainEventPublisher.STREAM_KEY, GROUP);
        } catch (Exception e) {
            // BUSYGROUP：组已存在，属正常情况
            if (e.getMessage() == null || !e.getMessage().contains("BUSYGROUP")) {
                log.debug("[事件消费] 创建消费组跳过：{}", e.getMessage());
            }
        }
    }

    /**
     * 处理单条事件。
     *
     * @return true 表示可 ACK；false 表示应重试
     */
    private boolean handle(StringRedisTemplate redis, MapRecord<String, Object, Object> record) {
        Map<Object, Object> fields = record.getValue();
        String eventId = str(fields.get("eventId"));
        String eventType = str(fields.get("eventType"));
        String orderId = str(fields.get("orderId"));

        if (eventId == null || eventId.isBlank()) {
            // 无 eventId 无法幂等，直接 ACK 丢弃，避免毒消息卡住队列
            log.warn("[事件消费] 事件缺少 eventId，已丢弃 type={}", eventType);
            return true;
        }

        // 幂等：用 setIfAbsent 原子抢占去重键（多实例安全）。
        // 抢占成功说明自己是第一个处理该事件的工作者；抢占失败说明另一实例正在处理或已处理过。
        // 先用短 TTL（5 分钟）作为处理中锁，处理成功后延长到 dedupHours。
        // 若处理失败不延长，短 TTL 过期后另一实例可重试。
        Boolean claimed = redis.opsForValue()
                .setIfAbsent(DEDUP_PREFIX + eventId, "1", Duration.ofMinutes(5));
        if (!Boolean.TRUE.equals(claimed)) {
            log.debug("[事件消费] 重复事件已跳过 eventId={} type={}", eventId, eventType);
            return true;
        }

        switch (eventType == null ? "" : eventType) {
            case DomainEventPublisher.ORDER_CREATED ->
                    log.info("[事件消费] 订单已创建，通知商户备餐 orderId={}", orderId);
            case DomainEventPublisher.ORDER_PAID ->
                    log.info("[事件消费] 订单已支付，触发商家接单提醒 orderId={}", orderId);
            case DomainEventPublisher.ORDER_CANCELLED ->
                    log.info("[事件消费] 订单已取消，触发库存/名额归还确认 orderId={}", orderId);
            case DomainEventPublisher.ORDER_REFUNDED ->
                    log.info("[事件消费] 订单已退款，触发财务对账记录 orderId={}", orderId);
            default -> log.info("[事件消费] 未识别事件类型 type={} orderId={}（已忽略）", eventType, orderId);
        }
        // 处理成功：延长去重键 TTL 到配置值，防止同一事件在 dedupHours 内被重复投递
        redis.expire(DEDUP_PREFIX + eventId, Duration.ofHours(Math.max(dedupHours, 1)));
        return true;
    }

    private String str(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
