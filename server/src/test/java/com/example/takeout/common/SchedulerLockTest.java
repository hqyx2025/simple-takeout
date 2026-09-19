package com.example.takeout.common;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 定时任务调度锁的行为测试。
 *
 * <p>这类锁的取舍与仓库既有口径一致（见 {@code LoginRateLimiter}）：</p>
 * <ul>
 *   <li><b>Redis 可用</b>：同一任务同一时刻只有一个实例执行，其余实例跳过。</li>
 *   <li><b>Redis 不可用 / 抛异常</b>：<b>放行执行</b>（fail-open）。锁只是削峰，
 *       不是正确性来源——被保护的任务（超时取消、Outbox 清理）本身已是条件更新/幂等，
 *       为了一把锁让定时任务整体停摆，代价远大于多跑一次的浪费。</li>
 * </ul>
 */
class SchedulerLockTest {

    private StringRedisTemplate redis;
    private ValueOperations<String, String> valueOps;
    private ObjectProvider<StringRedisTemplate> provider;
    private SchedulerLock lock;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() {
        redis = mock(StringRedisTemplate.class);
        valueOps = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(valueOps);

        provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);

        lock = new SchedulerLock(provider);
        ReflectionTestUtils.setField(lock, "enabled", true);
    }

    /** 抢到锁：动作必须执行。 */
    @Test
    void runsActionWhenLockAcquired() {
        when(valueOps.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(true);
        List<String> ran = new ArrayList<>();

        boolean executed = lock.tryRun("timeout-scan", Duration.ofSeconds(30), () -> ran.add("x"));

        assertTrue(executed);
        assertEquals(List.of("x"), ran, "抢到锁的实例必须执行任务");
    }

    /** 别的实例持锁：本实例必须跳过，不能重复执行。 */
    @Test
    void skipsActionWhenLockHeldByAnotherInstance() {
        when(valueOps.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(false);
        List<String> ran = new ArrayList<>();

        boolean executed = lock.tryRun("timeout-scan", Duration.ofSeconds(30), () -> ran.add("x"));

        assertFalse(executed);
        assertTrue(ran.isEmpty(), "未抢到锁时绝不能执行任务，否则多实例会重复处理");
    }

    /** Redis 不可用：必须 fail-open 执行，不能让定时任务整体停摆。 */
    @Test
    void runsActionWhenRedisUnavailable() {
        when(provider.getIfAvailable()).thenReturn(null);
        List<String> ran = new ArrayList<>();

        boolean executed = lock.tryRun("timeout-scan", Duration.ofSeconds(30), () -> ran.add("x"));

        assertTrue(executed, "Redis 不可用时必须放行——锁是削峰手段，不是正确性前提");
        assertEquals(List.of("x"), ran);
    }

    /** Redis 抛异常：同样 fail-open，且不能把异常抛给调用方（定时任务不得中断调度）。 */
    @Test
    void runsActionWhenRedisThrows() {
        when(valueOps.setIfAbsent(anyString(), anyString(), any(Duration.class)))
                .thenThrow(new RuntimeException("connection refused"));
        List<String> ran = new ArrayList<>();

        boolean executed = lock.tryRun("timeout-scan", Duration.ofSeconds(30), () -> ran.add("x"));

        assertTrue(executed);
        assertEquals(List.of("x"), ran);
    }

    /** 动作自身抛异常时必须向上传播（调用方已有 try/catch），且不能吞掉业务错误。 */
    @Test
    void propagatesActionFailure() {
        when(valueOps.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(true);

        boolean thrown = false;
        try {
            lock.tryRun("timeout-scan", Duration.ofSeconds(30), () -> {
                throw new IllegalStateException("boom");
            });
        } catch (IllegalStateException e) {
            thrown = true;
        }

        assertTrue(thrown, "任务自身的异常必须传播，由调用方按既有约定记录");
    }

    /** 开关关闭时不做加锁，直接执行（本地开发单实例无需 Redis 依赖）。 */
    @Test
    void runsDirectlyWhenDisabled() {
        ReflectionTestUtils.setField(lock, "enabled", false);
        List<String> ran = new ArrayList<>();

        boolean executed = lock.tryRun("timeout-scan", Duration.ofSeconds(30), () -> ran.add("x"));

        assertTrue(executed);
        assertEquals(List.of("x"), ran);
    }

    /** 不同任务的锁键必须互不干扰（超时扫描与 Outbox 清理各自独立）。 */
    @Test
    void differentTasksUseDifferentLockKeys() {
        when(valueOps.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(true);

        lock.tryRun("timeout-scan", Duration.ofSeconds(30), () -> { });
        lock.tryRun("outbox-cleanup", Duration.ofSeconds(30), () -> { });

        org.mockito.ArgumentCaptor<String> keys = org.mockito.ArgumentCaptor.forClass(String.class);
        org.mockito.Mockito.verify(valueOps, org.mockito.Mockito.times(2))
                .setIfAbsent(keys.capture(), anyString(), any(Duration.class));
        assertFalse(keys.getAllValues().get(0).equals(keys.getAllValues().get(1)),
                "不同任务必须用不同锁键，否则互相饿死：" + keys.getAllValues());
    }
}