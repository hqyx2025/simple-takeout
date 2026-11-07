package com.example.takeout.config;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class RocketMqSlf4jProviderTest {
    @Test void sdkProviderForwardsLevelsArgumentsMarkersAndExceptionsToApplicationLogging() throws Exception {
        String name = "mq-logging-test-" + java.util.UUID.randomUUID();
        Logger application = (Logger) org.slf4j.LoggerFactory.getLogger(name);
        application.setLevel(ch.qos.logback.classic.Level.INFO);
        var events = new ListAppender<ILoggingEvent>(); events.start(); application.addAppender(events);
        try {
            var sdk = org.apache.rocketmq.logging.org.slf4j.LoggerFactory.getLogger(name);
            assertFalse(sdk.isDebugEnabled());
            sdk.debug("disabled");
            sdk.info("event {}", 17);
            sdk.warn(org.apache.rocketmq.logging.org.slf4j.MarkerFactory.getMarker("RETRY"),
                    "attempt {}", 2, new IllegalStateException("offline"));
            assertEquals(2, events.list.size());
            assertEquals("event 17", events.list.get(0).getFormattedMessage());
            assertEquals("attempt 2", events.list.get(1).getFormattedMessage());
            assertEquals("RETRY", events.list.get(1).getMarkerList().getFirst().getName());
            assertEquals(IllegalStateException.class.getName(), events.list.get(1).getThrowableProxy().getClassName());
            assertThrows(ClassNotFoundException.class, () -> Class.forName("org.apache.rocketmq.logging.ch.qos.logback.classic.LoggerContext"));
        } finally { application.detachAppender(events); events.stop(); }
    }

    @Test void sdkAndApplicationMdcShareCorrelationWithoutAnIsolatedLoggingContext() {
        try {
            org.apache.rocketmq.logging.org.slf4j.MDC.put("traceId", "mq-origin");
            assertEquals("mq-origin", org.slf4j.MDC.get("traceId"));
            org.slf4j.MDC.put("traceId", "app-origin");
            assertEquals("app-origin", org.apache.rocketmq.logging.org.slf4j.MDC.get("traceId"));
        } finally { org.slf4j.MDC.clear(); }
    }
}
