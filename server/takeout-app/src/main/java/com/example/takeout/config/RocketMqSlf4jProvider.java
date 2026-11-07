package com.example.takeout.config;

import org.apache.rocketmq.logging.org.slf4j.ILoggerFactory;
import org.apache.rocketmq.logging.org.slf4j.IMarkerFactory;
import org.apache.rocketmq.logging.org.slf4j.Marker;
import org.apache.rocketmq.logging.org.slf4j.event.Level;
import org.apache.rocketmq.logging.org.slf4j.helpers.AbstractLogger;
import org.apache.rocketmq.logging.org.slf4j.helpers.BasicMarkerFactory;
import org.apache.rocketmq.logging.org.slf4j.spi.MDCAdapter;
import org.apache.rocketmq.logging.org.slf4j.spi.SLF4JServiceProvider;

import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Route the SDK's isolated SLF4J API to Boot's supported logger, without its obsolete bundled Logback. */
public final class RocketMqSlf4jProvider implements SLF4JServiceProvider {
    private final Map<String, org.apache.rocketmq.logging.org.slf4j.Logger> loggers = new ConcurrentHashMap<>();
    private final ILoggerFactory factory = name -> loggers.computeIfAbsent(name, BridgeLogger::new);
    private final IMarkerFactory markers = new BasicMarkerFactory();
    private final MDCAdapter mdc = new ApplicationMdc();

    @Override public ILoggerFactory getLoggerFactory() { return factory; }
    @Override public IMarkerFactory getMarkerFactory() { return markers; }
    @Override public MDCAdapter getMDCAdapter() { return mdc; }
    @Override public String getRequestedApiVersion() { return "2.0.99"; }
    @Override public void initialize() { }

    private static org.slf4j.Marker applicationMarker(Marker marker) {
        return marker == null ? null : org.slf4j.MarkerFactory.getMarker(marker.getName());
    }

    private static final class BridgeLogger extends AbstractLogger {
        private final org.slf4j.Logger delegate;
        BridgeLogger(String name) { this.name = name; delegate = org.slf4j.LoggerFactory.getLogger(name); }
        @Override protected String getFullyQualifiedCallerName() { return BridgeLogger.class.getName(); }
        @Override protected void handleNormalizedLoggingCall(Level level, Marker marker, String message, Object[] args, Throwable error) {
            var event = delegate.atLevel(org.slf4j.event.Level.valueOf(level.name())).setCause(error);
            if (marker != null) event.addMarker(applicationMarker(marker));
            event.log(message, args == null ? new Object[0] : args);
        }
        @Override public boolean isTraceEnabled() { return delegate.isTraceEnabled(); }
        @Override public boolean isDebugEnabled() { return delegate.isDebugEnabled(); }
        @Override public boolean isInfoEnabled() { return delegate.isInfoEnabled(); }
        @Override public boolean isWarnEnabled() { return delegate.isWarnEnabled(); }
        @Override public boolean isErrorEnabled() { return delegate.isErrorEnabled(); }
        @Override public boolean isTraceEnabled(Marker m) { return delegate.isTraceEnabled(applicationMarker(m)); }
        @Override public boolean isDebugEnabled(Marker m) { return delegate.isDebugEnabled(applicationMarker(m)); }
        @Override public boolean isInfoEnabled(Marker m) { return delegate.isInfoEnabled(applicationMarker(m)); }
        @Override public boolean isWarnEnabled(Marker m) { return delegate.isWarnEnabled(applicationMarker(m)); }
        @Override public boolean isErrorEnabled(Marker m) { return delegate.isErrorEnabled(applicationMarker(m)); }
    }

    private static final class ApplicationMdc implements MDCAdapter {
        private org.slf4j.spi.MDCAdapter delegate() { return org.slf4j.MDC.getMDCAdapter(); }
        @Override public void put(String key, String value) { delegate().put(key, value); }
        @Override public String get(String key) { return delegate().get(key); }
        @Override public void remove(String key) { delegate().remove(key); }
        @Override public void clear() { delegate().clear(); }
        @Override public Map<String,String> getCopyOfContextMap() { return delegate().getCopyOfContextMap(); }
        @Override public void setContextMap(Map<String,String> context) { delegate().setContextMap(context); }
        @Override public void pushByKey(String key, String value) { delegate().pushByKey(key, value); }
        @Override public String popByKey(String key) { return delegate().popByKey(key); }
        @Override public Deque<String> getCopyOfDequeByKey(String key) { return delegate().getCopyOfDequeByKey(key); }
        @Override public void clearDequeByKey(String key) { delegate().clearDequeByKey(key); }
    }
}
