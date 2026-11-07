package com.example.takeout.security;

import java.time.Duration;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.LongSupplier;

/** 无等待的故障短路；每个恢复周期只允许一个探测，旧在途结果不能覆盖新一轮状态。 */
final class AvailabilityCircuit {
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(AvailabilityCircuit.class);
    record Ticket(long generation, boolean probe) {}
    private record State(long generation, int failures, long retryAt, boolean probing) {}
    private final AtomicReference<State> state = new AtomicReference<>(new State(0, 0, 0, false));
    private final int threshold;
    private final long cooldown;
    private final LongSupplier clock;
    private final String name;

    AvailabilityCircuit(String name, int threshold, Duration cooldown, LongSupplier clock) {
        this.name = name;
        this.threshold = threshold;
        this.cooldown = cooldown.toNanos();
        this.clock = clock;
    }

    Ticket acquire() {
        while (true) {
            State current = state.get();
            if (current.retryAt() == 0) return new Ticket(current.generation(), false);
            if (current.probing() || clock.getAsLong() - current.retryAt() < 0) return null;
            State probe = new State(current.generation(), current.failures(), current.retryAt(), true);
            if (state.compareAndSet(current, probe)) return new Ticket(probe.generation(), true);
        }
    }

    void success(Ticket ticket) { complete(ticket, false, false); }
    void failure(Ticket ticket) { complete(ticket, true, false); }
    void abandon(Ticket ticket) { complete(ticket, false, true); }

    private void complete(Ticket ticket, boolean failed, boolean abandoned) {
        while (true) {
            State current = state.get();
            if (current.generation() != ticket.generation()) return;
            State next;
            if (abandoned) {
                if (!ticket.probe() || !current.probing()) return;
                next = new State(current.generation() + 1, current.failures(), clock.getAsLong(), false);
            } else if (failed) {
                int failures = current.failures() + 1;
                next = failures >= threshold || ticket.probe()
                        ? new State(current.generation() + 1, failures, clock.getAsLong() + cooldown, false)
                        : new State(current.generation(), failures, 0, false);
            } else {
                next = new State(current.generation() + (ticket.probe() ? 1 : 0), 0, 0, false);
            }
            if (state.compareAndSet(current, next)) {
                if (failed && next.retryAt() != 0 && (!current.probing() || current.retryAt() == 0)) {
                    log.warn("领券/抢单保护暂停访问 dependency={} cooldownMs={}", name, Duration.ofNanos(cooldown).toMillis());
                } else if (!failed && !abandoned && ticket.probe()) {
                    log.info("领券/抢单保护探测恢复 dependency={}", name);
                }
                return;
            }
        }
    }
}
