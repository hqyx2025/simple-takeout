package com.example.takeout.service.mq;

import com.example.takeout.dao.OutboxEventDao;
import com.example.takeout.common.TraceContext;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.data.redis.connection.stream.StreamRecords;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/**
 * 领域事件发布器（事务性 Outbox + Redis Stream）。
 *
 * <p><b>设计要点：为什么不用「下单后直接发消息」？</b>
 * 下单是一个本地事务，扣库存、占秒杀名额、核销优惠券必须原子提交。
 * 如果在事务内直接写 Redis，Redis 成功但数据库回滚就会产生「幽灵订单事件」；
 * 如果提交后再写 Redis，进程在两者之间崩溃又会丢事件。因此这里采用
 * <b>事务性 Outbox</b>：事件先以同一事务写入数据库 {@code outbox_events} 表
 * （要么和订单一起提交，要么一起回滚，绝不丢失或凭空产生），
 * 再由 {@link OutboxRelayJob} 异步搬运到 Redis Stream。</p>
 *
 * <p><b>为什么订单主流程保持同步？</b>
 * 秒杀/库存的防超卖依赖数据库条件更新（{@code WHERE stock >= ?}、
 * {@code sold + ? <= quota}）在本地事务内的原子性。把下单本身改成异步
 * 需要引入 saga 与补偿事务，收益（吞吐）远小于复杂度与一致性风险，
 * 因此异步化只覆盖「可延迟」的下游动作（通知、报表、埋点等）。</p>
 *
 * <p>Redis 不可用时：事件仍然安全落在数据库 outbox 表中，等待重投，
 * 业务主流程完全不受影响（与缓存层同样的降级思路）。</p>
 */
@Service
public class DomainEventPublisher {

    private static final Logger log = LoggerFactory.getLogger(DomainEventPublisher.class);

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /** Stream 键名。 */
    public static final String STREAM_KEY = "takeout:stream:domain-events";

    private static final org.springframework.data.redis.core.script.RedisScript<Long> TRIM_ACKNOWLEDGED =
            org.springframework.data.redis.core.script.RedisScript.of("""
                local length = redis.call('XLEN', KEYS[1])
                local target = tonumber(ARGV[1])
                if length <= target then return 0 end
                local groups = redis.call('XINFO', 'GROUPS', KEYS[1])
                if #groups == 0 then return 0 end
                local function less(a, b)
                  local am, as = string.match(a, '^(%d+)%-(%d+)$')
                  local bm, bs = string.match(b, '^(%d+)%-(%d+)$')
                  if #am ~= #bm then return #am < #bm end
                  if am ~= bm then return am < bm end
                  if #as ~= #bs then return #as < #bs end
                  return as < bs
                end
                local safe = nil
                for _, group in ipairs(groups) do
                  local name, delivered, pending
                  for i = 1, #group, 2 do
                    if group[i] == 'name' then name = group[i+1] end
                    if group[i] == 'last-delivered-id' then delivered = group[i+1] end
                    if group[i] == 'pending' then pending = tonumber(group[i+1]) end
                  end
                  if not delivered or delivered == '0-0' then return 0 end
                  local boundary = delivered
                  if pending > 0 then boundary = redis.call('XPENDING', KEYS[1], name)[2] end
                  if not safe or less(boundary, safe) then safe = boundary end
                end
                local candidates = redis.call('XRANGE', KEYS[1], '-', '+', 'COUNT', math.min(length-target, 100))
                if #candidates == 0 then return 0 end
                local cutoff = candidates[#candidates][1]
                if less(safe, cutoff) then cutoff = safe end
                return redis.call('XTRIM', KEYS[1], 'MINID', cutoff)
                """, Long.class);

    /** 事件类型常量。 */
    public static final String ORDER_CREATED = "ORDER_CREATED";
    public static final String ORDER_PAID = "ORDER_PAID";
    public static final String ORDER_CANCELLED = "ORDER_CANCELLED";
    public static final String ORDER_REFUNDED = "ORDER_REFUNDED";
    public static final String ORDER_SETTLED = "ORDER_SETTLED";

    private final OutboxEventDao outboxDao;
    private final ObjectProvider<StringRedisTemplate> redisProvider;
    private final ObjectMapper objectMapper;

    @Value("${takeout.mq.enabled:true}")
    private boolean enabled = true;

    @Value("${takeout.mq.stream-maxlen:10000}")
    private long streamMaxLen = 10000;

    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private com.example.takeout.service.ErpEventDelivery erpDelivery;

    public DomainEventPublisher(OutboxEventDao outboxDao, ObjectProvider<StringRedisTemplate> redisProvider,
                                ObjectMapper objectMapper) {
        this.outboxDao = outboxDao;
        this.redisProvider = redisProvider;
        this.objectMapper = objectMapper;
    }

    /**
     * 记录一个领域事件。
     *
     * <p>若当前处于事务中，事件会随事务一起提交（Outbox 语义）；
     * 若不在事务中，则立即落库并由后续中继投递。</p>
     */
    public void publish(String eventType, long orderId, Map<String, Object> payload) {
        if (!enabled) {
            return;
        }
        String json;
        try {
            Map<String,Object> fields = new java.util.LinkedHashMap<>(payload == null ? Map.of() : payload);
            // Persist correlation with the event; retries never depend on the originating HTTP thread.
            if (!TraceContext.current().isBlank()) fields.put("_traceId", TraceContext.current());
            json = objectMapper.writeValueAsString(fields);
        } catch (Exception e) {
            throw new IllegalStateException("Outbox event serialization failed", e);
        }
        try {
            outboxDao.insert(eventType, orderId, json, LocalDateTime.now().format(FMT));
        } catch (org.springframework.dao.DataAccessException e) {
            // MySQL 死锁可能已回滚整个事务，不能吞异常后继续返回业务成功。
            throw e;
        } catch (Exception e) {
            throw new IllegalStateException("Outbox event persistence failed", e);
        }
    }

    /**
     * 立即把单条事件投递到 Redis Stream（供中继任务调用）。
     *
     * @return true 表示投递成功
     */
    public boolean deliver(long eventId, String eventType, long orderId, String payloadJson) {
        StringRedisTemplate redis = redisProvider.getIfAvailable();
        if (redis == null) {
            return false;
        }
        String previous = TraceContext.current();
        String trace = null;
        try {
            var payload = objectMapper.readTree(payloadJson == null ? "{}" : payloadJson);
            if (payload != null) trace = TraceContext.normalize(payload.path("_traceId").asText(null));
        } catch (Exception ignored) {
            // Legacy events without valid metadata remain deliverable.
        }
        TraceContext.bind(trace == null ? "event-" + eventId : trace);
        try {
            if (erpDelivery != null && !erpDelivery.deliver(eventId,eventType,orderId,payloadJson)) return false;
            Map<String, String> fields = Map.of(
                    "eventId", String.valueOf(eventId),
                    "eventType", eventType,
                    "orderId", String.valueOf(orderId),
                    "payload", payloadJson == null ? "{}" : payloadJson,
                    "occurredAt", LocalDateTime.now().format(FMT),
                    "traceId", TraceContext.current());
            MapRecord<String, String, String> record = StreamRecords.mapBacked(fields).withStreamKey(STREAM_KEY);
            redis.opsForStream().add(record);
            // Retention is a target: pending/unread messages are never sacrificed to a length cap.
            // Redis noeviction supplies the hard memory boundary; failed XADD stays in the durable Outbox.
            if (streamMaxLen > 0) {
                try {
                    redis.execute(TRIM_ACKNOWLEDGED, java.util.List.of(STREAM_KEY), String.valueOf(streamMaxLen));
                } catch (Exception ignored) {
                    // 裁剪失败不影响投递结果
                }
            }
            log.info("[事件] 投递完成 eventId={} type={}", eventId, eventType);
            return true;
        } catch (Exception e) {
            log.warn("[事件] ERP/Stream 下游投递失败 eventId={} type={}（等待 Outbox 退避重试）", eventId, eventType, e);
            return false;
        } finally {
            TraceContext.clear();
            TraceContext.bind(previous);
        }
    }

    /** 供诊断使用：当前是否启用事件机制。 */
    public boolean isEnabled() {
        return enabled;
    }

    /**
     * 事务提交后再执行的动作（用于把「通知」等副作用推迟到提交之后）。
     * 事务提交后回调，回滚则不执行。
     */
    public static void afterCommit(Runnable action) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    action.run();
                }
            });
        } else {
            action.run();
        }
    }
}
