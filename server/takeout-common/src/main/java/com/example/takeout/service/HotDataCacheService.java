package com.example.takeout.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Supplier;

/**
 * 热点数据缓存服务（Redis）。
 *
 * <p>只缓存「读多写少、可容忍短暂延迟一致」的浏览类热点数据：首页分类、店铺列表/详情、
 * 店内菜品、特价菜、榜单、限时秒杀、Banner 与公告。购物车、订单、余额、库存等强一致数据
 * 一律不进缓存，仍直接走数据库。</p>
 *
 * <p>三类缓存故障的防护策略：</p>
 * <ul>
 *   <li><b>缓存穿透</b>（查询不存在的数据，请求全部打到数据库）：不存在的对象也会写入一个
 *       短的「空值占位」缓存（{@link #NULL_MARKER}），使同一非法 key 在 nullTtl 内不再落库；
 *       业务键映射到 512 个固定槽，值携带完整业务键校验碰撞；动态槽编码后最多 64 KiB，八个固定目录按配置上限。</li>
 *   <li><b>缓存击穿</b>（热点 key 恰好在过期瞬间被高并发回源）：回源前用 Redis
 *       {@code SET NX} 抢分布式互斥锁，只有一个请求查库并回填，其余请求短暂自旋等待后复用结果；
 *       等不到锁的请求直接回源（降级），保证不会因为锁而阻塞业务。</li>
 *   <li><b>缓存雪崩</b>（大批 key 同时过期或 Redis 整体不可用）：写入时 TTL 叠加随机抖动
 *       （baseTtl + [0, jitter)），把过期时刻打散；任意一次 Redis 异常都只记日志并回源数据库，
 *       绝不把缓存故障升级成业务故障。</li>
 * </ul>
 *
 * <p>序列化统一使用 JSON 文本（{@link StringRedisTemplate}），值中带业务键与 JSON 载荷，
 * 读取时按调用方给出的 {@link java.lang.reflect.Type} 反序列化。</p>
 */
@Service
public class HotDataCacheService implements org.springframework.beans.factory.InitializingBean {

    private static final Logger log = LoggerFactory.getLogger(HotDataCacheService.class);

    /** 空值占位标记：命中它表示「该数据在数据库中确实不存在」，用于防穿透。 */
    private static final String NULL_MARKER = "\u0000NULL\u0000";

    /** 击穿保护锁的 key 后缀。 */
    private static final String LOCK_SUFFIX = ":lock";
    private static final int CACHE_SLOTS = 512;
    private static final int MAX_DYNAMIC_ENTRY_BYTES = 64 * 1024;
    @Value("${takeout.cache.max-entry-bytes:1048576}")
    private long maxEntryBytes = 1048576;
    private final java.util.concurrent.atomic.AtomicLongArray oversizeWarningAt =
            new java.util.concurrent.atomic.AtomicLongArray(CACHE_SLOTS);
    private record CacheEntry(String key, String value) {}
    private static final java.util.Map<String,Integer> SHARED_SLOTS = java.util.Map.of(
            Keys.CATEGORIES, 0, Keys.BANNERS, 1, Keys.ANNOUNCEMENTS, 2, Keys.ALL_STORES, 3,
            Keys.RECOMMENDED_STORES, 4, Keys.SPECIAL_GOODS, 5, Keys.RANK_GOODS, 6, Keys.SECKILLS, 7);

    private final ObjectProvider<StringRedisTemplate> redisProvider;
    private final ObjectMapper objectMapper;

    @Value("${takeout.cache.enabled:true}")
    private boolean enabled = true;

    @Value("${takeout.cache.key-prefix:takeout:}")
    private String keyPrefix = "takeout:";

    /** 基础 TTL（秒）。 */
    @Value("${takeout.cache.ttl-seconds:300}")
    private long ttlSeconds = 300;

    /** TTL 随机抖动上限（秒），用于打散过期时刻防雪崩。 */
    @Value("${takeout.cache.jitter-seconds:120}")
    private long jitterSeconds = 120;

    /** 空值占位 TTL（秒），防穿透；明显短于正常 TTL。 */
    @Value("${takeout.cache.null-ttl-seconds:60}")
    private long nullTtlSeconds = 60;

    /** 回源互斥锁持有时长（毫秒）。 */
    @Value("${takeout.cache.rebuild-lock-ms:3000}")
    private long rebuildLockMs = 3000;

    /** 未抢到锁时等待并重试读缓存的总时长（毫秒）。 */
    @Value("${takeout.cache.rebuild-wait-ms:500}")
    private long rebuildWaitMs = 500;

    private static final DefaultRedisScript<Long> UNLOCK_SCRIPT = new DefaultRedisScript<>(
            "if redis.call('get', KEYS[1]) == ARGV[1] then " +
                    "return redis.call('del', KEYS[1]) else return 0 end", Long.class);

    public HotDataCacheService(ObjectProvider<StringRedisTemplate> redisProvider, ObjectMapper objectMapper) {
        this.redisProvider = redisProvider;
        this.objectMapper = objectMapper;
    }
    @Override public void afterPropertiesSet() {
        if (maxEntryBytes < 65536 || maxEntryBytes > 4194304) {
            throw new IllegalStateException("固定目录缓存单值上限必须为 65536 到 4194304 字节");
        }
    }
    /**
     * 读缓存，未命中则回源并回填。
     *
     * @param key     业务 key（不含前缀），与缓存结果一一对应；实际存储由固定槽位约束
     * @param typeRef 反序列化目标类型（如 {@code new TypeReference<List<Category>>() {}}）
     * @param loader  回源函数；返回 null 表示数据不存在，将写入空值占位
     */
    public <T> T get(String key, com.fasterxml.jackson.core.type.TypeReference<T> typeRef, Supplier<T> loader) {
        String redisKey = storageKey(key);
        StringRedisTemplate redis = redis();

        // 1) 读缓存：Redis 故障时直接回源，缓存问题不影响业务
        if (redis != null) {
            String cached = safeGet(redis, redisKey, key);
            if (NULL_MARKER.equals(cached)) {
                // 空值占位命中：直接返回「不存在」，不查库（防穿透）
                return null;
            }
            if (cached != null) {
                T parsed = deserialize(cached, typeRef);
                if (parsed != null) {
                    return parsed;
                }
                // 反序列化失败（如模型结构变更）：删除脏缓存并按未命中处理
                safeDelete(redis, redisKey);
            }
        }

        // 2) 回源：用分布式锁保证同一 key 同一时刻只有一个请求查库（防击穿）
        T loaded;
        String token = null;
        if (redis != null) {
            token = tryLock(redis, redisKey, key);
            if (token == null) {
                // 没抢到锁：等一会儿看别人是否已回填，避免重复查库
                T waited = awaitRebuild(redis, redisKey, key, typeRef);
                if (waited != null || isNullMarked(redis, redisKey, key)) {
                    return waited;
                }
                // 等不到就自己回源（降级），保证请求不被锁拖死
            }
        }

        try {
            loaded = loadAndFill(redis, redisKey, key, typeRef, loader);
        } finally {
            // 回源失败也必须立即释放自己的锁，否则所有请求会被无意义地挡到 TTL 到期。
            if (redis != null && token != null) {
                unlock(redis, redisKey, token);
            }
        }
        return loaded;
    }

    /** 回源查库并写入缓存（含空值占位）。 */
    private <T> T loadAndFill(StringRedisTemplate redis, String redisKey, String key,
                              com.fasterxml.jackson.core.type.TypeReference<T> typeRef, Supplier<T> loader) {
        T loaded;
        try {
            loaded = loader.get();
        } catch (RuntimeException e) {
            // 回源失败：不写缓存，异常照常上抛，避免把失败结果缓存成空值
            throw e;
        }
        if (redis == null) {
            return loaded;
        }
        if (loaded == null) {
            safeSet(redis, redisKey, key, NULL_MARKER, nullTtlSeconds);
            return null;
        }
        String json = serialize(loaded);
        if (json != null) {
            safeSet(redis, redisKey, key, json, ttlWithJitter());
        }
        return loaded;
    }

    /**
     * 同一业务身份才等待回填；其他身份或无法识别的锁立即回源，保留持有者的锁。
     */
    private <T> T awaitRebuild(StringRedisTemplate redis, String redisKey, String key,
                               com.fasterxml.jackson.core.type.TypeReference<T> typeRef) {
        long deadline = System.currentTimeMillis() + Math.max(rebuildWaitMs, 0);
        long sleepMs = 20;
        while (System.currentTimeMillis() < deadline) {
            String cached = safeGet(redis, redisKey, key);
            if (NULL_MARKER.equals(cached)) return null;
            if (cached != null) return deserialize(cached, typeRef);
            // 同槽不同业务键不共享重建结果；锁记录完整身份，值尚未回填时也能区分。
            if (!key.equals(lockOwner(redis, redisKey))) {
                // 持有者可能刚好在上次读取后完成回填并释放锁，再核对一次已完成的结果。
                String completed = safeGet(redis, redisKey, key);
                return completed == null || NULL_MARKER.equals(completed) ? null : deserialize(completed, typeRef);
            }
            try {
                long remaining = deadline - System.currentTimeMillis();
                if (remaining <= 0) return null;
                Thread.sleep(Math.min(sleepMs, remaining));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return null;
            }
            sleepMs = Math.min(sleepMs * 2, 80);
        }
        return null;
    }

    /** 判断 key 是否已被标记为空值占位（等待锁时用）。 */
    private boolean isNullMarked(StringRedisTemplate redis, String redisKey, String key) {
        return NULL_MARKER.equals(safeGet(redis, redisKey, key));
    }

    /** 只删除缓存，不写空值：用于「写操作后失效」场景，避免失效瞬间的读请求被占位挡住。 */
    public void evict(String... keys) {
        StringRedisTemplate redis = redis();
        if (redis == null || keys == null) {
            return;
        }
        for (String key : keys) {
            if (key != null) {
                safeDelete(redis, storageKey(key));
            }
        }
    }

    /**
     * 按模式请求失效；固定槽位可能承载任意业务键，因此保守清除整个热点数据区。
     * 使用 SCAN 而非 KEYS，避免在大 key 空间下阻塞 Redis。
     */
    public void evictByPattern(String pattern) {
        StringRedisTemplate redis = redis();
        if (redis == null || pattern == null) {
            return;
        }
        String match = keyPrefix + "hot:v3:*";
        try {
            var options = org.springframework.data.redis.core.ScanOptions.scanOptions().match(match).count(200).build();
            try (var cursor = redis.scan(options)) {
                while (cursor.hasNext()) {
                    String key = cursor.next();
                    if (!key.endsWith(LOCK_SUFFIX)) safeDelete(redis, key);
                }
            }
        } catch (Exception e) {
            log.warn("[缓存失效] 按模式清理失败 pattern={}", match, e);
        }
    }

    // ============ 内部工具：所有 Redis 操作都不允许抛出业务可见异常 ============

    /** 固定物理键空间：512 个值槽 + 512 个回源锁，碰撞按完整业务键判为未命中。 */
    String storageKey(String businessKey) {
        Integer shared = SHARED_SLOTS.get(businessKey);
        int slot = shared != null ? shared : SHARED_SLOTS.size()
                + Math.floorMod(businessKey.hashCode(), CACHE_SLOTS - SHARED_SLOTS.size());
        return keyPrefix + "hot:v3:" + slot;
    }

    /** 取 Redis 客户端；未配置或总开关关闭时返回 null，调用方回源数据库。 */
    private StringRedisTemplate redis() {
        if (!enabled) {
            return null;
        }
        return redisProvider.getIfAvailable();
    }

    private String safeGet(StringRedisTemplate redis, String key, String businessKey) {
        try {
            String raw = redis.opsForValue().get(key);
            if (raw == null) return null;
            CacheEntry entry = objectMapper.readValue(raw, CacheEntry.class);
            return businessKey.equals(entry.key()) ? entry.value() : null;
        } catch (Exception e) {
            log.warn("[缓存读取] 失败 key={}，本次回源数据库", key, e);
            return null;
        }
    }

    private void safeSet(StringRedisTemplate redis, String key, String businessKey, String value, long ttl) {
        try {
            String encoded = objectMapper.writeValueAsString(new CacheEntry(businessKey, value));
            int bytes = encoded.getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
            long limit = SHARED_SLOTS.containsKey(businessKey) ? maxEntryBytes : Math.min(maxEntryBytes, MAX_DYNAMIC_ENTRY_BYTES);
            if (bytes > limit) {
                warnOversize(businessKey, key, bytes, limit);
                return;
            }
            redis.opsForValue().set(key, encoded, Duration.ofSeconds(Math.max(ttl, 1)));
        } catch (Exception e) {
            log.warn("[缓存写入] 失败 key={}", key, e);
        }
    }

    private void warnOversize(String businessKey, String redisKey, int bytes, long limit) {
        int slot = Integer.parseInt(redisKey.substring(redisKey.lastIndexOf(':') + 1));
        long now = System.nanoTime();
        long previous = oversizeWarningAt.get(slot);
        if (previous != 0 && now - previous < java.util.concurrent.TimeUnit.MINUTES.toNanos(1)) return;
        if (oversizeWarningAt.compareAndSet(slot, previous, now)) {
            log.warn("[缓存容量] 跳过回填 key={} slot={} bytes={} limit={}，同槽告警每分钟最多一次",
                    businessKey, redisKey, bytes, limit);
        }
    }

    private void safeDelete(StringRedisTemplate redis, String key) {
        try {
            redis.delete(key);
        } catch (Exception e) {
            log.warn("[缓存删除] 失败 key={}", key, e);
        }
    }

    /** 抢回源互斥锁，成功返回唯一 token（用于安全释放），失败返回 null。 */
    private String tryLock(StringRedisTemplate redis, String redisKey, String businessKey) {
        try {
            String token = objectMapper.writeValueAsString(new CacheEntry(businessKey, java.util.UUID.randomUUID().toString()));
            Boolean ok = redis.opsForValue().setIfAbsent(redisKey + LOCK_SUFFIX, token,
                    Duration.ofMillis(Math.max(rebuildLockMs, 1)));
            return Boolean.TRUE.equals(ok) ? token : null;
        } catch (Exception e) {
            log.warn("[缓存击穿保护] 加锁失败 key={}，本次直接回源", redisKey, e);
            return null;
        }
    }

    private String lockOwner(StringRedisTemplate redis, String redisKey) {
        try {
            String raw = redis.opsForValue().get(redisKey + LOCK_SUFFIX);
            return raw == null ? null : objectMapper.readValue(raw, CacheEntry.class).key();
        } catch (Exception e) {
            // 不认识的锁或故障不能让无关请求等待；仍保留原锁，不擅自释放。
            return null;
        }
    }

    /** 释放锁：仅当 token 仍属于自己时删除，避免误删他人锁。 */
    private void unlock(StringRedisTemplate redis, String redisKey, String token) {
        String lockKey = redisKey + LOCK_SUFFIX;
        try {
            // GET 后再 DEL 在 TTL 到期并被新请求抢锁的窗口里可能误删新锁，
            // 用 Redis Lua 保证「校验 token + 删除」是一个原子操作。
            redis.execute(UNLOCK_SCRIPT, List.of(lockKey), token);
        } catch (Exception e) {
            log.warn("[缓存击穿保护] 释放锁失败 key={}（将由 TTL 自动过期）", lockKey, e);
        }
    }

    /** 计算带随机抖动的 TTL，打散过期时刻，防缓存雪崩。 */
    private long ttlWithJitter() {
        long base = Math.max(ttlSeconds, 1);
        long jitter = Math.max(jitterSeconds, 0);
        return base + (jitter > 0 ? ThreadLocalRandom.current().nextLong(jitter) : 0);
    }

    private String serialize(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (Exception e) {
            log.warn("[缓存序列化] 失败 type={}，本次不写缓存", value.getClass().getName(), e);
            return null;
        }
    }

    private <T> T deserialize(String json, com.fasterxml.jackson.core.type.TypeReference<T> typeRef) {
        try {
            return objectMapper.readValue(json, typeRef);
        } catch (Exception e) {
            log.warn("[缓存反序列化] 失败，按未命中处理", e);
            return null;
        }
    }

    /** 供运维接口/测试使用：当前是否启用缓存。 */
    public boolean isEnabled() {
        return enabled;
    }

    /** 供运维接口/测试使用：缓存键前缀。 */
    public String keyPrefix() {
        return keyPrefix;
    }

    /** 清空本应用命名空间下的全部热点缓存。 */
    public void evictAll() {
        evictByPattern("*");
    }

    /** 常用 key 常量集合：集中定义，杜绝散落的字符串拼接。 */
    public static final class Keys {
        private Keys() {
        }

        public static final String CATEGORIES = "categories";
        public static final String BANNERS = "banners";
        public static final String ANNOUNCEMENTS = "announcements";

        public static String storeGoods(long storeId) {
            return "store:" + storeId + ":goods";
        }

        public static String storeCategories(long storeId) {
            return "store:" + storeId + ":categories";
        }

        public static final String ALL_STORES = "stores:source:all";
        public static final String RECOMMENDED_STORES = "stores:source:recommended";
        public static final String SPECIAL_GOODS = "goods:source:special";
        public static final String RANK_GOODS = "goods:source:rank";
        public static final String SECKILLS = "seckills:source:active";

        /** 缓存不含用户坐标的原始目录；距离、半径和数量在读取后计算。 */
        public static String storeList(Integer categoryId) {
            return categoryId == null || categoryId == 0 ? ALL_STORES : "stores:source:category:" + categoryId;
        }

        public static String storeSource(long storeId) {
            return "store:" + storeId + ":source";
        }

        /** 所有与店铺/商品展示相关的缓存（店铺或商品变更时整体失效）。 */
        public static final List<String> STORE_GOODS_PATTERNS = List.of(
                "stores:*", "store:*", "goods:*", "rank:*", "seckills:*", "categories");

        /**
         * 库存/秒杀名额变化时需要失效的缓存模式。
         * 菜品库存与秒杀 sold 参与店铺列表、店内菜品、特价菜、榜单与秒杀专区的展示筛选，
         * 下单扣减与取消回滚后必须让这些视图重新计算。
         */
        public static final List<String> STOCK_DEPENDENT_PATTERNS = List.of(
                "stores:*", "store:*", "goods:*", "rank:*", "seckills:*");
    }
}
