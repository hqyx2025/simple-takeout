package com.example.takeout.service.mq;

/** Stable envelope; the Outbox ID remains unchanged across delivery retries. */
public record DomainEvent(long eventId, String eventType, long orderId, String payload, String traceId) { }
