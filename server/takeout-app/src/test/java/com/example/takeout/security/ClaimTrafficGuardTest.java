package com.example.takeout.security;

import com.example.takeout.common.BizException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.CannotGetJdbcConnectionException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class ClaimTrafficGuardTest {
    static ClaimTrafficSettings settings(int capacity, int rps, int failures) {
        return new ClaimTrafficSettings(capacity, rps, rps, failures,
                Duration.ofSeconds(5), Duration.ofSeconds(5), Duration.ofSeconds(30));
    }

    @Test void capacityIsSharedAcrossActionsAndRejectsWithoutQueuing() {
        var jdbc = mock(JdbcTemplate.class);
        var guard = new ClaimTrafficGuard(mock(ObjectProvider.class), jdbc, settings(2, 100, 3));
        try (var first = guard.enter(ClaimTrafficGuard.Action.COUPON); var second = guard.enter(ClaimTrafficGuard.Action.RIDER)) {
            assertEquals(503, assertThrows(BizException.class, () -> guard.enter(ClaimTrafficGuard.Action.COUPON)).getCode());
            verifyNoInteractions(jdbc);
        }
        try (var next = guard.enter(ClaimTrafficGuard.Action.COUPON)) { next.admit(null); }
    }

    @Test void totalBudgetIsAtomicAcrossManyAccountsAndRestoresNextWindow() throws Exception {
        AtomicLong clock = new AtomicLong(1_000_000_000L);
        var guard = new ClaimTrafficGuard(mock(ObjectProvider.class), mock(JdbcTemplate.class), settings(32, 5, 3), clock::get);
        CountDownLatch start = new CountDownLatch(1);
        try (var pool = Executors.newFixedThreadPool(32)) {
            var results = new ArrayList<Future<Boolean>>();
            for (int i = 0; i < 32; i++) results.add(pool.submit(() -> {
                assertTrue(start.await(5, TimeUnit.SECONDS));
                try (var lease = guard.enter(ClaimTrafficGuard.Action.COUPON)) { lease.admit(null); return true; }
                catch (BizException e) { assertEquals(429, e.getCode()); return false; }
            }));
            start.countDown();
            int accepted = 0;
            for (var result : results) if (result.get(5, TimeUnit.SECONDS)) accepted++;
            assertEquals(5, accepted);
        }
        clock.addAndGet(Duration.ofSeconds(1).toNanos());
        try (var lease = guard.enter(ClaimTrafficGuard.Action.COUPON)) { lease.admit(null); }
    }

    @Test void localOrderFilterSurvivesRedisOutageAndReleasesAfterFailure() {
        var guard = new ClaimTrafficGuard(mock(ObjectProvider.class), mock(JdbcTemplate.class), settings(4, 100, 3));
        try (var first = guard.enter(ClaimTrafficGuard.Action.RIDER)) {
            first.admit("900");
            try (var second = guard.enter(ClaimTrafficGuard.Action.RIDER)) {
                assertEquals(409, assertThrows(BizException.class, () -> second.admit("900")).getCode());
            }
            try (var another = guard.enter(ClaimTrafficGuard.Action.RIDER)) { another.admit("901"); }
        }
        try (var retry = guard.enter(ClaimTrafficGuard.Action.RIDER)) { retry.admit("900"); }
    }

    @Test void outageOpensCircuitAndOnlyOneRealProbeCanRestoreIt() {
        AtomicLong clock = new AtomicLong(1_000_000_000L);
        var jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject("SELECT 1", Integer.class)).thenReturn(1);
        var guard = new ClaimTrafficGuard(mock(ObjectProvider.class), jdbc, settings(4, 100, 3), clock::get);
        // 保留一个旧请求，验证其迟到的成功不能关闭后来打开的熔断。
        try (var stale = guard.enter(ClaimTrafficGuard.Action.COUPON)) {
            for (int i = 0; i < 3; i++) try (var lease = guard.enter(ClaimTrafficGuard.Action.COUPON)) {
                lease.admit(null); lease.failed();
            }
            stale.succeeded(true);
            assertEquals(503, assertThrows(BizException.class, () -> guard.enter(ClaimTrafficGuard.Action.RIDER)).getCode());
        }
        verifyNoInteractions(jdbc);
        clock.addAndGet(Duration.ofSeconds(5).toNanos());
        try (var probe = guard.enter(ClaimTrafficGuard.Action.COUPON)) {
            probe.admit(null);
            verify(jdbc).queryForObject("SELECT 1", Integer.class);
            assertEquals(503, assertThrows(BizException.class, () -> guard.enter(ClaimTrafficGuard.Action.RIDER)).getCode());
            probe.succeeded(false); // 只有真实 SELECT 1 成功才能在没有认证结果时恢复。
        }
        try (var recovered = guard.enter(ClaimTrafficGuard.Action.RIDER)) { recovered.admit("900"); }
    }

    @Test void failedRecoveryProbeReopensAndUnauthenticatedCallsCannotCloseCircuit() {
        AtomicLong clock = new AtomicLong(1_000_000_000L);
        var jdbc = mock(JdbcTemplate.class);
        var guard = new ClaimTrafficGuard(mock(ObjectProvider.class), jdbc, settings(4, 100, 1), clock::get);
        try (var lease = guard.enter(ClaimTrafficGuard.Action.COUPON)) { lease.failed(); }
        clock.addAndGet(Duration.ofSeconds(5).toNanos());
        try (var unauthenticated = guard.enter(ClaimTrafficGuard.Action.COUPON)) { unauthenticated.succeeded(false); }
        when(jdbc.queryForObject("SELECT 1", Integer.class)).thenThrow(new CannotGetJdbcConnectionException("offline"));
        try (var probe = guard.enter(ClaimTrafficGuard.Action.COUPON)) {
            assertEquals(503, assertThrows(BizException.class, () -> probe.admit(null)).getCode());
        }
        assertEquals(503, assertThrows(BizException.class, () -> guard.enter(ClaimTrafficGuard.Action.COUPON)).getCode());
        verify(jdbc, times(1)).queryForObject("SELECT 1", Integer.class);
    }
}
