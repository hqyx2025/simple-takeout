package com.example.takeout.common;

import org.junit.jupiter.api.Test;

import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * 雪花 ID 生成器测试。
 *
 * <p>为什么必须换掉原来的「时间戳 + 4 位随机数」：秒级时间戳只有 1 秒粒度，
 * 同一秒内的并发下单只能靠 4 位随机数（9000 个取值）区分——生日问题下，
 * 1000 笔同秒订单的碰撞概率已超过 99%，撞上就是一个 UNIQUE 冲突失败给用户看。</p>
 */
class SnowflakeIdGeneratorTest {

    @Test
    void generatesUniqueIdsUnderConcurrency() throws Exception {
        SnowflakeIdGenerator generator = new SnowflakeIdGenerator(1L);
        int threads = 16;
        int perThread = 2000;
        Set<Long> ids = ConcurrentHashMap.newKeySet();
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        try {
            for (int t = 0; t < threads; t++) {
                pool.submit(() -> {
                    try {
                        start.await();
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        return;
                    }
                    for (int i = 0; i < perThread; i++) {
                        ids.add(generator.nextId());
                    }
                });
            }
            start.countDown();
            pool.shutdown();
            assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS), "生成必须在超时内完成");
        } finally {
            pool.shutdownNow();
        }
        // 16 * 2000 = 32000 个 ID，必须零重复（同毫秒内的序列号保证）
        assertEquals(threads * perThread, ids.size(), "并发下不得产生重复 ID");
    }

    @Test
    void idsAreMonotonicallyIncreasingWithinSingleThread() {
        SnowflakeIdGenerator generator = new SnowflakeIdGenerator(1L);
        List<Long> ids = IntStream.range(0, 5000).mapToObj(i -> generator.nextId()).collect(Collectors.toList());

        for (int i = 1; i < ids.size(); i++) {
            assertTrue(ids.get(i) > ids.get(i - 1),
                    "同一线程内 ID 必须严格递增（便于按 ID 排序）：" + ids.get(i - 1) + " -> " + ids.get(i));
        }
    }

    @Test
    void idsAreOrderedAcrossDifferentWorkers() {
        // 不同实例（workerId 不同）在同一时刻生成的 ID，高位时间戳仍保证大致有序
        SnowflakeIdGenerator a = new SnowflakeIdGenerator(1L);
        SnowflakeIdGenerator b = new SnowflakeIdGenerator(2L);

        long idA = a.nextId();
        long idB = b.nextId();

        assertTrue(Math.abs(idA - idB) < (1L << 42), "不同 worker 的 ID 差异应只体现在低位：" + idA + " vs " + idB);
    }

    @Test
    void rejectsOutOfRangeWorkerId() {
        assertFalse(SnowflakeIdGenerator.isValidWorkerId(-1L), "负 workerId 必须被拒绝");
        assertFalse(SnowflakeIdGenerator.isValidWorkerId(1024L), "超出 10 位上限的 workerId 必须被拒绝");
        assertTrue(SnowflakeIdGenerator.isValidWorkerId(0L));
        assertTrue(SnowflakeIdGenerator.isValidWorkerId(1023L));
    }

    @Test
    void idAsStringIsPositiveDigitsOnly() {
        SnowflakeIdGenerator generator = new SnowflakeIdGenerator(1L);

        String value = generator.nextIdString();

        assertTrue(value.matches("\\d+"), "订单号必须只含数字，便于展示与索引：" + value);
        assertTrue(value.length() <= 32, "订单号必须能放进 orders.order_no VARCHAR(32)：" + value);
    }

    @Test
    void requiresExplicitValidWorkerId() {
        for (String value : new String[]{null, "", " ", "host-a", "-1", "1024", "1.0"}) {
            assertThrows(IllegalArgumentException.class, () -> BusinessIdGenerator.configuredWorkerId(value));
        }
        assertEquals(0, BusinessIdGenerator.configuredWorkerId("0"));
        assertEquals(1023, BusinessIdGenerator.configuredWorkerId(" 1023 "));
    }

    @Test
    void clockRollbackDoesNotProduceDuplicateIds() {
        // 时钟回拨：不能倒退序号导致重复 ID，必须自旋等待或抛错，绝不静默产出重复值
        SnowflakeIdGenerator generator = new SnowflakeIdGenerator(1L, () -> 1_800_000_000_000L);
        Set<Long> ids = new HashSet<>();
        for (int i = 0; i < 100; i++) {
            ids.add(generator.nextId());
        }
        assertEquals(100, ids.size(), "固定时钟（模拟回拨停摆）下仍不得产生重复 ID");
    }

    @Test
    void exposesNoDuplicateAcrossBatchesAfterClockRollback() {
        long[] clock = {1_800_000_000_000L};
        SnowflakeIdGenerator generator = new SnowflakeIdGenerator(1L, () -> clock[0]);
        Set<Long> ids = new HashSet<>(Collections.singletonList(generator.nextId()));
        // 模拟时钟回拨 5ms
        clock[0] -= 5;
        assertThrows(IllegalStateException.class, generator::nextId);
        clock[0] += 5;
        ids.add(generator.nextId());

        assertEquals(2, ids.size(), "时钟回拨也不得产生重复 ID：" + ids);
    }

    @Test
    void exhaustedSequenceNeverFakesTimeOrReusesAnIdAfterFailedWait() {
        long[] clock = {1_800_000_000_000L};
        var generator = new SnowflakeIdGenerator(7, () -> clock[0]);
        Set<Long> ids = new HashSet<>();
        for (int i = 0; i < 4096; i++) assertTrue(ids.add(generator.nextId()));
        assertThrows(IllegalStateException.class, generator::nextId);
        assertThrows(IllegalStateException.class, generator::nextId);
        clock[0]++;
        assertTrue(ids.add(generator.nextId()));
    }

    @Test
    void waitsForSmallRollbackButRejectsLargeRollbackAndInvalidEpoch() {
        long now = 1_800_000_000_000L;
        var clock = new java.util.concurrent.atomic.AtomicLong(now);
        var generator = new SnowflakeIdGenerator(7, clock::getAndIncrement);
        long first = generator.nextId();
        clock.set(now - 5);
        assertTrue(generator.nextId() > first);
        clock.set(now - 6);
        assertThrows(IllegalStateException.class, generator::nextId);
        assertThrows(IllegalStateException.class, () -> new SnowflakeIdGenerator(7, () -> 0).nextId());
        assertThrows(IllegalStateException.class, () -> new SnowflakeIdGenerator(7,
                () -> 1_767_225_600_000L + (1L << 41)).nextId());
    }

    @Test
    void fullIdsStayDistinctAcrossTheOldSevenDigitWraparound() {
        long[] clock = {1_800_000_000_000L};
        var generator = new SnowflakeIdGenerator(7, () -> clock[0]);
        long first = generator.nextId();
        clock[0] += 78_125;
        long second = generator.nextId();
        assertEquals(first % 10_000_000, second % 10_000_000);
        assertTrue(second > first);
        long businessId = Long.parseLong(BusinessIdGenerator.nextId());
        long timestamp = (businessId >>> 22) + 1_767_225_600_000L;
        assertTrue(Math.abs(System.currentTimeMillis() - timestamp) < 1000,
                "业务入口必须保留完整雪花时间位，不能再拼日期或截断");
        assertEquals(BusinessIdGenerator.workerId(), (businessId >>> 12) & 1023);
    }
}
