package com.example.takeout.service.mq;

import com.example.takeout.dao.DomainEventInbox;
import com.example.takeout.dao.OutboxEventDao;
import com.example.takeout.config.RocketMqConfiguration;
import com.example.takeout.job.OutboxRelayJob;
import com.example.takeout.service.PushNotificationService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.rocketmq.client.consumer.listener.ConsumeConcurrentlyStatus;
import org.apache.rocketmq.client.consumer.listener.MessageListenerConcurrently;
import org.apache.rocketmq.client.producer.DefaultMQProducer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Creates and drops only a random test database; never writes to the application schema. */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class DomainEventInboxMySqlTest {
    private JdbcTemplate admin;
    private String schema;
    private JdbcTemplate jdbc;
    private TransactionTemplate transactions;
    private DomainEventInbox inbox;

    @BeforeEach void open() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1") + ":"
                + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        admin = new JdbcTemplate(new DriverManagerDataSource(base + options, user, password));
        schema = "takeout_mq_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE `" + schema + "`");
        var source = new DriverManagerDataSource(base + schema + options, user, password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql"),
                new ClassPathResource("db/migration/app/V3__rocketmq_consumption_receipts.sql"),
                new ClassPathResource("db/migration/app/V4__mq_failure_tracking_and_replay_lock.sql")).execute(source);
        jdbc = new JdbcTemplate(source);
        transactions = new TransactionTemplate(new DataSourceTransactionManager(source));
        inbox = new DomainEventInbox(jdbc, transactions);
        jdbc.execute("CREATE TABLE mq_test_effects(id BIGINT PRIMARY KEY, amount INT NOT NULL) ENGINE=InnoDB");
        jdbc.update("INSERT INTO mq_test_effects VALUES(1,0)");
    }

    @AfterEach void close() {
        if (admin != null && schema != null) admin.execute("DROP DATABASE `" + schema + "`");
    }

    @Test void failedConsumptionRollsBackEffectAndReceiptThenRetryCommitsOnlyOnce() {
        assertThrows(IllegalStateException.class, () -> inbox.runOnce("notifications", 17, () -> {
            jdbc.update("UPDATE mq_test_effects SET amount=amount+100 WHERE id=1");
            throw new IllegalStateException("injected downstream failure");
        }));
        assertEquals(0, amount());
        assertEquals(0, count("mq_consumptions"));
        Runnable effect = () -> jdbc.update("UPDATE mq_test_effects SET amount=amount+100 WHERE id=1");
        inbox.runOnce("notifications", 17, effect);
        inbox.runOnce("notifications", 17, effect);
        assertEquals(100, amount(), "a duplicate event must not repeat the durable effect");
        assertEquals(1, completed());
        inbox.runOnce("another-group", 17, effect);
        assertEquals(200, amount(), "each independent group owns its own receipt");
        assertEquals(2, completed());
    }

    @Test void overlappingConsumersSerializeTheSameEventAndPersistOneEffect() throws Exception {
        var firstEntered = new CountDownLatch(1);
        var secondStarted = new CountDownLatch(1);
        var releaseFirst = new CountDownLatch(1);
        var secondInbox = new DomainEventInbox(jdbc, transactions);
        try (var pool = Executors.newFixedThreadPool(2)) {
            var first = pool.submit(() -> inbox.runOnce("notifications", 23, () -> {
                firstEntered.countDown();
                try { assertTrue(releaseFirst.await(5, TimeUnit.SECONDS)); }
                catch (InterruptedException e) { throw new IllegalStateException(e); }
                jdbc.update("UPDATE mq_test_effects SET amount=amount+100 WHERE id=1");
            }));
            assertTrue(firstEntered.await(5, TimeUnit.SECONDS));
            var second = pool.submit(() -> {
                secondStarted.countDown();
                secondInbox.runOnce("notifications", 23,
                        () -> jdbc.update("UPDATE mq_test_effects SET amount=amount+100 WHERE id=1"));
            });
            assertTrue(secondStarted.await(5, TimeUnit.SECONDS));
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
            boolean overlapping = false;
            while (System.nanoTime() < deadline) {
                overlapping = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.processlist "
                        + "WHERE DB=? AND INFO LIKE 'INSERT INTO mq_consumptions%'", Integer.class, schema) > 0;
                if (overlapping) break;
                Thread.sleep(20);
            }
            releaseFirst.countDown();
            first.get(10, TimeUnit.SECONDS);
            second.get(10, TimeUnit.SECONDS);
            assertTrue(overlapping, "the second SQL request must overlap the first uncommitted consumption");
        } finally { releaseFirst.countDown(); }
        assertEquals(100, amount());
        assertEquals(1, completed());
    }

    @Test void durableFailureAgeSurvivesRetriesAndNewInstancesUntilSuccessfulConsumption() {
        String key = DomainEventInbox.failureKey(17, "");
        inbox.recordFailure("notifications", key, 17);
        jdbc.update("UPDATE mq_consumer_failures SET first_failed_at=CURRENT_TIMESTAMP(6)-INTERVAL 6 MINUTE");
        inbox.recordFailure("notifications", key, 17);
        var restarted = new DomainEventInbox(jdbc, transactions);
        assertEquals(1, restarted.failures("notifications").count());
        assertTrue(restarted.failures("notifications").oldestSeconds() >= 360);
        assertEquals(2, jdbc.queryForObject("SELECT attempts FROM mq_consumer_failures", Integer.class));
        assertEquals(0, completed());
        assertThrows(IllegalStateException.class, () -> restarted.runOnce("notifications", 17,
                () -> { throw new IllegalStateException("provider still unavailable"); }));
        assertEquals(1, restarted.failures("notifications").count());
        assertTrue(restarted.failures("notifications").oldestSeconds() >= 360);
        restarted.runOnce("notifications", 17, () -> jdbc.update("UPDATE mq_test_effects SET amount=100 WHERE id=1"));
        assertEquals(100, amount());
        assertEquals(0, restarted.failures("notifications").count());
        inbox.recordFailure("notifications", key, 17); // A slower failed replica must not reopen a completed event.
        assertEquals(0, inbox.failures("notifications").count());
        assertEquals(1, completed());
    }

    @Test @SuppressWarnings("unchecked")
    void outboxAndBusinessMutationCommitAndRollbackTogether() {
        var outbox = new OutboxEventDao(jdbc, transactions);
        var publisher = new DomainEventPublisher(outbox, mock(ObjectProvider.class), new ObjectMapper());
        assertThrows(IllegalStateException.class, () -> transactions.executeWithoutResult(status -> {
            jdbc.update("UPDATE mq_test_effects SET amount=100 WHERE id=1");
            publisher.publish(DomainEventPublisher.ORDER_PAID, 21, Map.of("amount", 100));
            throw new IllegalStateException("injected business failure");
        }));
        assertEquals(0, amount());
        assertEquals(0, count("outbox_events"));
        transactions.executeWithoutResult(status -> {
            jdbc.update("UPDATE mq_test_effects SET amount=100 WHERE id=1");
            publisher.publish(DomainEventPublisher.ORDER_PAID, 21, Map.of("amount", 100));
        });
        assertEquals(100, amount());
        assertEquals(1, outbox.countPending(), "broker availability must not decide business commit");
        assertFalse(publisher.deliver(outbox.listPending(1).getFirst().id(), "ORDER_PAID", 21, "{}"));
        assertEquals(1, outbox.countPending(), "unconfirmed delivery must remain recoverable");
    }

    @Test @SuppressWarnings("unchecked")
    @EnabledIfEnvironmentVariable(named = "TAKEOUT_ROCKETMQ_TEST", matches = "1")
    void realBrokerRetainsBacklogAndRedeliversFailureWithoutRepeatingCommittedEffect() throws Exception {
        var configuration = new RocketMqConfiguration();
        String namesrv = System.getenv().getOrDefault("TAKEOUT_ROCKETMQ_NAMESRV_ADDR", "localhost:9876");
        String topic = System.getenv().getOrDefault("TAKEOUT_ROCKETMQ_TOPIC", "takeout-test-domain-events");
        String group = System.getenv().getOrDefault("TAKEOUT_ROCKETMQ_CONSUMER_GROUP", "takeout-test-notifications");
        ReflectionTestUtils.setField(configuration, "namesrvAddr", namesrv);
        ReflectionTestUtils.setField(configuration, "topic", topic);
        ReflectionTestUtils.setField(configuration, "consumerGroup", group);
        var producer = new DefaultMQProducer("takeout-test-producer-" + UUID.randomUUID());
        producer.setNamesrvAddr(namesrv);
        producer.setVipChannelEnabled(false);
        producer.setInstanceName(UUID.randomUUID().toString());
        producer.setSendMsgTimeout(3000);
        var brokerConsumer = configuration.newConsumer();
        brokerConsumer.setInstanceName(UUID.randomUUID().toString());
        var delivered = new CountDownLatch(2);
        var retried = new CountDownLatch(1);
        var attempts = new java.util.concurrent.atomic.AtomicInteger();
        try {
            producer.start();
            ObjectProvider<DefaultMQProducer> producers = mock(ObjectProvider.class);
            when(producers.getIfAvailable()).thenReturn(producer);
            var outbox = new OutboxEventDao(jdbc, transactions);
            var mapper = new ObjectMapper();
            var publisher = new DomainEventPublisher(outbox, producers, mapper);
            ReflectionTestUtils.setField(publisher, "topic", topic);
            var notifications = mock(PushNotificationService.class);
            doAnswer(call -> {
                if (attempts.incrementAndGet() == 1) throw new IllegalStateException("injected push outage");
                jdbc.update("UPDATE mq_test_effects SET amount=amount+100 WHERE id=1");
                return null;
            }).when(notifications).notifyOrderEvent(anyString(), anyLong());
            ObjectProvider<PushNotificationService> pushes = mock(ObjectProvider.class);
            when(pushes.getIfAvailable()).thenReturn(notifications);
            var handler = new DomainEventConsumer(configuration, inbox, mapper, pushes);
            brokerConsumer.registerMessageListener((MessageListenerConcurrently) (messages, context) -> {
                var result = handler.consumeMessage(messages, context);
                if (result == ConsumeConcurrentlyStatus.CONSUME_SUCCESS) {
                    delivered.countDown();
                    if (messages.stream().anyMatch(message -> message.getReconsumeTimes() > 0)) retried.countDown();
                }
                return result;
            });
            transactions.executeWithoutResult(status -> {
                publisher.publish(DomainEventPublisher.ORDER_PAID, 21, Map.of("amount", 100));
            });
            var event = outbox.listPending(1).getFirst();
            new OutboxRelayJob(outbox, publisher, mock(com.example.takeout.common.SchedulerLock.class)).relay();
            assertEquals(0, outbox.countPending());
            assertEquals(1, outbox.findById(event.id()).orElseThrow().status());
            assertTrue(publisher.deliver(event.id(), event.eventType(), event.orderId(), event.payload()));
            assertEquals(0, completed(), "messages are sent before the consumer exists");
            brokerConsumer.start();
            assertTrue(delivered.await(45, TimeUnit.SECONDS), "backlog and retry must be consumed");
            assertTrue(retried.await(30, TimeUnit.SECONDS), "the broker must actually redeliver the failed message");
            assertEquals(100, amount());
            assertEquals(1, completed());
            assertEquals(2, attempts.get(), "one failed attempt, one committed effect; duplicates skip the effect");
        } finally {
            brokerConsumer.shutdown();
            producer.shutdown();
        }
    }

    @Test @SuppressWarnings("unchecked")
    @EnabledIfEnvironmentVariable(named = "TAKEOUT_ROCKETMQ_TEST", matches = "1")
    void realDeadLetterIsObservableAndReplayPreservesTheEventAndDurableDeduplication() throws Exception {
        var configuration = new RocketMqConfiguration();
        String namesrv = System.getenv().getOrDefault("TAKEOUT_ROCKETMQ_NAMESRV_ADDR", "localhost:9876");
        String topic = "takeout-ops-" + UUID.randomUUID();
        String group = "takeout-ops-group-" + UUID.randomUUID();
        ReflectionTestUtils.setField(configuration, "namesrvAddr", namesrv);
        ReflectionTestUtils.setField(configuration, "topic", topic);
        ReflectionTestUtils.setField(configuration, "consumerGroup", group);
        var bootstrap = configuration.newAdmin();
        bootstrap.setInstanceName("bootstrap-" + UUID.randomUUID());
        var producer = new DefaultMQProducer("takeout-ops-producer-" + UUID.randomUUID());
        producer.setNamesrvAddr(namesrv);
        producer.setVipChannelEnabled(false);
        producer.setInstanceName(UUID.randomUUID().toString());
        var brokerConsumer = configuration.newConsumer();
        brokerConsumer.setInstanceName("dlq-" + UUID.randomUUID());
        brokerConsumer.setMaxReconsumeTimes(0); // Exercise a real broker DLQ without waiting through 16 backoffs.
        var registry = new io.micrometer.core.instrument.simple.SimpleMeterRegistry();
        var operations = new RocketMqOperations(configuration, producer, new ObjectMapper(), registry, inbox);
        var pushOffline = new java.util.concurrent.atomic.AtomicBoolean(true);
        try {
            bootstrap.start();
            String broker = System.getenv().getOrDefault("TAKEOUT_ROCKETMQ_BROKER_ADDR", "127.0.0.1:10911");
            bootstrap.createAndUpdateTopicConfig(broker, new org.apache.rocketmq.common.TopicConfig(topic, 1, 1));
            for (String name : java.util.List.of(group, group + "-replay")) {
                var subscription = new org.apache.rocketmq.remoting.protocol.subscription.SubscriptionGroupConfig();
                subscription.setGroupName(name);
                bootstrap.createAndUpdateSubscriptionGroupConfig(broker, subscription);
            }
            bootstrap.updateConsumeOffset(broker, group,
                    new org.apache.rocketmq.common.message.MessageQueue(topic, "takeout-broker", 0), 0);
            producer.start();
            ObjectProvider<DefaultMQProducer> producers = mock(ObjectProvider.class);
            when(producers.getIfAvailable()).thenReturn(producer);
            var outbox = new OutboxEventDao(jdbc, transactions);
            var publisher = new DomainEventPublisher(outbox, producers, new ObjectMapper());
            ReflectionTestUtils.setField(publisher, "topic", topic);
            transactions.executeWithoutResult(status -> publisher.publish("ORDER_PAID", 21, Map.of("amount", 100)));
            long eventId = outbox.listPending(1).getFirst().id();
            new OutboxRelayJob(outbox, publisher, mock(com.example.takeout.common.SchedulerLock.class)).relay();
            assertEquals(0, outbox.countPending());
            operations.refresh();
            assertEquals(1, operations.snapshot().available());
            assertEquals(1, operations.snapshot().pending(), "accepted but unconsumed messages must remain visible");
            assertEquals(0, operations.snapshot().deadLetters());

            var notifications = mock(PushNotificationService.class);
            var firstFailure = new CountDownLatch(1);
            doAnswer(call -> {
                if (pushOffline.get()) {
                    firstFailure.countDown();
                    throw new IllegalStateException("injected push outage");
                }
                jdbc.update("UPDATE mq_test_effects SET amount=amount+100 WHERE id=1");
                return null;
            }).when(notifications).notifyOrderEvent(anyString(), anyLong());
            ObjectProvider<PushNotificationService> pushes = mock(ObjectProvider.class);
            when(pushes.getIfAvailable()).thenReturn(notifications);
            var handler = new DomainEventConsumer(configuration, inbox, new ObjectMapper(), pushes);
            brokerConsumer.registerMessageListener(handler);
            brokerConsumer.start();
            assertTrue(firstFailure.await(45, TimeUnit.SECONDS), "the message must first be assigned to this new client");
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
            do {
                operations.refresh();
                if (operations.snapshot().deadLetters() == 1) break;
                Thread.sleep(100);
            } while (System.nanoTime() < deadline);
            assertEquals(1, operations.snapshot().deadLetters(), "real failed delivery must enter the DLQ");
            assertEquals(0, amount());
            assertEquals(0, completed());
            pushOffline.set(false);
            assertEquals(1, operations.replayDeadLetters(10));
            deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20);
            while (amount() != 100 && System.nanoTime() < deadline) Thread.sleep(100);
            assertEquals(100, amount());
            assertEquals(1, completed());
            assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM mq_consumptions WHERE event_id=? "
                    + "AND consumer_group=? AND consumed_at IS NOT NULL", Integer.class, eventId, group));
            operations.refresh();
            assertEquals(0, operations.snapshot().deadLetters(), "a confirmed replay must advance the durable replay cursor");
            assertEquals(0, operations.replayDeadLetters(10), "repeated replay must not publish acknowledged dead letters again");
            assertEquals(100, amount());
        } finally {
            operations.shutdown();
            brokerConsumer.shutdown();
            producer.shutdown();
            bootstrap.shutdown();
            registry.close();
        }
    }

    @Test @SuppressWarnings("unchecked")
    @EnabledIfEnvironmentVariable(named = "TAKEOUT_ROCKETMQ_TEST", matches = "1")
    void realDeferredRetryKeepsFailureVisibleAcrossNewInstancesAndClearsOnlyAfterSuccess() throws Exception {
        var registry = new io.micrometer.core.instrument.simple.SimpleMeterRegistry();
        try (var broker = new MqFixture()) {
            var config = broker.configuration("delay");
            var pushes = mock(PushNotificationService.class);
            var offline = new java.util.concurrent.atomic.AtomicBoolean(true);
            doAnswer(call -> {
                if (offline.get()) throw new IllegalStateException("injected provider outage");
                jdbc.update("UPDATE mq_test_effects SET amount=amount+100 WHERE id=1");
                return null;
            }).when(pushes).notifyOrderEvent(anyString(), anyLong());
            ObjectProvider<PushNotificationService> provider = mock(ObjectProvider.class);
            when(provider.getIfAvailable()).thenReturn(pushes);
            var handler = new DomainEventConsumer(config, inbox, new ObjectMapper(), provider);
            var failed = new CountDownLatch(1);
            var attempt = new java.util.concurrent.atomic.AtomicInteger();
            broker.consumer = config.newConsumer();
            broker.consumer.registerMessageListener((MessageListenerConcurrently) (messages, context) -> {
                attempt.set(messages.getFirst().getReconsumeTimes());
                var result = handler.consumeMessage(messages, context);
                failed.countDown();
                return result;
            });
            String retryTopic = "%RETRY%" + broker.group;
            broker.bootstrap.createAndUpdateTopicConfig(broker.address, new org.apache.rocketmq.common.TopicConfig(retryTopic, 1, 1));
            broker.bootstrap.updateConsumeOffset(broker.address, broker.group,
                    new org.apache.rocketmq.common.message.MessageQueue(retryTopic, "takeout-broker", 0), 0);
            var message = broker.envelope(retryTopic, 17);
            // Accelerate to a real late retry; Broker's default next delay is 20 minutes. No 20-minute wait is claimed.
            org.apache.rocketmq.common.message.MessageAccessor.putProperty(message,
                    org.apache.rocketmq.common.message.MessageConst.PROPERTY_RECONSUME_TIME, "12");
            org.apache.rocketmq.common.message.MessageAccessor.putProperty(message,
                    org.apache.rocketmq.common.message.MessageConst.PROPERTY_RETRY_TOPIC, broker.topic);
            broker.producer.send(message);
            broker.consumer.start();
            assertTrue(failed.await(45, TimeUnit.SECONDS), "the seeded attempt must first be assigned to this new client");
            assertEquals(12, attempt.get());
            jdbc.update("UPDATE mq_consumer_failures SET first_failed_at=CURRENT_TIMESTAMP(6)-INTERVAL 6 MINUTE");
            var restartedInbox = new DomainEventInbox(jdbc, transactions);
            var operations = new RocketMqOperations(broker.configuration("new-instance"), broker.producer,
                    new ObjectMapper(), registry, restartedInbox);
            try {
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15);
                do {
                    operations.refresh();
                    if (operations.snapshot().available() == 1 && operations.snapshot().pending() == 0
                            && operations.snapshot().failed() == 1) break;
                    Thread.sleep(100);
                } while (System.nanoTime() < deadline);
                assertEquals(1, operations.snapshot().available());
                assertEquals(0, operations.snapshot().pending());
                assertEquals(0, operations.snapshot().deadLetters());
                assertEquals(1, operations.snapshot().failed(), "deferred events must not appear healthy");
                assertTrue(operations.snapshot().oldestFailureSeconds() >= 360);
                broker.consumer.shutdown();
                offline.set(false);
                broker.consumer = config.newConsumer();
                broker.consumer.setInstanceName("recovered-" + UUID.randomUUID());
                broker.consumer.registerMessageListener(handler);
                broker.consumer.start();
                // An explicit successful retry avoids waiting for the seeded 20-minute Broker timer.
                broker.producer.send(broker.envelope(broker.topic, 17));
                // Reallocation to a restarted client follows Broker/client rebalance intervals.
                deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
                while (completed() != 1 && System.nanoTime() < deadline) Thread.sleep(100);
                assertEquals(1, completed());
                assertEquals(100, amount());
                operations.refresh();
                assertEquals(0, operations.snapshot().failed());
            } finally { operations.shutdown(); }
        } finally { registry.close(); }
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "TAKEOUT_ROCKETMQ_TEST", matches = "1")
    void twoReplayInstancesSerializeBeforeReadingTheRealBrokerCursor() throws Exception {
        var firstRegistry = new io.micrometer.core.instrument.simple.SimpleMeterRegistry();
        var secondRegistry = new io.micrometer.core.instrument.simple.SimpleMeterRegistry();
        try (var broker = new MqFixture()) {
            String deadTopic = "%DLQ%" + broker.group;
            broker.bootstrap.createAndUpdateTopicConfig(broker.address, new org.apache.rocketmq.common.TopicConfig(deadTopic, 1, 1));
            broker.producer.send(broker.envelope(deadTopic, 21));
            broker.producer.send(broker.envelope(deadTopic, 22));
            var firstSending = new CountDownLatch(1);
            var releaseFirst = new CountDownLatch(1);
            var sends = new java.util.concurrent.atomic.AtomicInteger();
            var publisher = spy(broker.producer);
            doAnswer(call -> {
                Object result = call.callRealMethod();
                if (sends.incrementAndGet() == 1) {
                    firstSending.countDown();
                    assertTrue(releaseFirst.await(8, TimeUnit.SECONDS));
                }
                return result;
            }).when(publisher).send(any(org.apache.rocketmq.common.message.Message.class));
            var first = new RocketMqOperations(broker.configuration("first"), publisher,
                    new ObjectMapper(), firstRegistry, new DomainEventInbox(jdbc, transactions));
            var second = new RocketMqOperations(broker.configuration("second"), publisher,
                    new ObjectMapper(), secondRegistry, new DomainEventInbox(jdbc, transactions));
            try (var workers = Executors.newFixedThreadPool(2)) {
                var a = workers.submit(() -> first.replayDeadLetters(1));
                assertTrue(firstSending.await(8, TimeUnit.SECONDS));
                var b = workers.submit(() -> second.replayDeadLetters(2));
                boolean waitingOnLock = false;
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
                while (!b.isDone() && System.nanoTime() < deadline) {
                    waitingOnLock = jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.processlist "
                            + "WHERE DB=? AND INFO LIKE 'INSERT INTO mq_replay_locks%'", Integer.class, schema) > 0;
                    if (waitingOnLock) break;
                    Thread.sleep(20);
                }
                releaseFirst.countDown();
                assertEquals(1, a.get(10, TimeUnit.SECONDS));
                assertEquals(1, b.get(10, TimeUnit.SECONDS));
                assertTrue(waitingOnLock, "two independent clients must actually overlap at the shared SQL lock");
                assertEquals(2, sends.get(), "a stale request must not republish the first dead letter");
                var queue = new org.apache.rocketmq.common.message.MessageQueue(deadTopic, "takeout-broker", 0);
                long committed = broker.bootstrap.examineConsumeStats(broker.address, broker.group + "-replay", deadTopic, 3000)
                        .getOffsetTable().get(queue).getConsumerOffset();
                assertEquals(2, committed, "the slower one-message request must not rewind a two-message cursor");
                assertEquals(0, second.replayDeadLetters(2));
            } finally {
                releaseFirst.countDown();
                first.shutdown();
                second.shutdown();
            }
        } finally { firstRegistry.close(); secondRegistry.close(); }
    }

    @Test @SuppressWarnings("unchecked")
    @EnabledIfEnvironmentVariable(named = "TAKEOUT_ROCKETMQ_TEST", matches = "1")
    void realTrackingWriteFailureRetriesQuicklyAndBecomesDurablyVisibleAfterRecovery() throws Exception {
        var registry = new io.micrometer.core.instrument.simple.SimpleMeterRegistry();
        try (var broker = new MqFixture()) {
            String retryTopic = "%RETRY%" + broker.group;
            broker.bootstrap.createAndUpdateTopicConfig(broker.address, new org.apache.rocketmq.common.TopicConfig(retryTopic, 1, 1));
            broker.bootstrap.updateConsumeOffset(broker.address, broker.group,
                    new org.apache.rocketmq.common.message.MessageQueue(retryTopic, "takeout-broker", 0), 0);
            var tracking = spy(inbox);
            doThrow(new org.springframework.dao.DataAccessResourceFailureException("injected tracking-write outage"))
                    .doCallRealMethod().when(tracking).recordFailure(anyString(), anyString(), anyLong());
            var pushes = mock(PushNotificationService.class);
            doThrow(new IllegalStateException("provider offline")).when(pushes).notifyOrderEvent(anyString(), anyLong());
            ObjectProvider<PushNotificationService> provider = mock(ObjectProvider.class);
            when(provider.getIfAvailable()).thenReturn(pushes);
            var handler = new DomainEventConsumer(broker.configuration("tracking"), tracking, new ObjectMapper(), provider);
            var firstAttempt = new CountDownLatch(1);
            var recovered = new CountDownLatch(1);
            broker.consumer = broker.configuration("tracking-consumer").newConsumer();
            broker.consumer.registerMessageListener((MessageListenerConcurrently) (messages, context) -> {
                var status = handler.consumeMessage(messages, context);
                firstAttempt.countDown();
                if (messages.getFirst().getReconsumeTimes() >= 13) recovered.countDown();
                return status;
            });
            var message = broker.envelope(retryTopic, 17);
            org.apache.rocketmq.common.message.MessageAccessor.putProperty(message,
                    org.apache.rocketmq.common.message.MessageConst.PROPERTY_RECONSUME_TIME, "12");
            org.apache.rocketmq.common.message.MessageAccessor.putProperty(message,
                    org.apache.rocketmq.common.message.MessageConst.PROPERTY_RETRY_TOPIC, broker.topic);
            broker.producer.send(message);
            broker.consumer.start();
            assertTrue(firstAttempt.await(45, TimeUnit.SECONDS), "the seeded attempt must first be assigned to this new client");
            assertTrue(recovered.await(15, TimeUnit.SECONDS), "tracking recovery must not wait for the default 20-minute backoff");
            verify(tracking, atLeast(2)).recordFailure(broker.group, "event-17", 17);
            var operations = new RocketMqOperations(broker.configuration("tracking-metrics"), broker.producer,
                    new ObjectMapper(), registry, inbox);
            try {
                operations.refresh();
                assertEquals(1, operations.snapshot().available());
                assertEquals(1, operations.snapshot().failed());
                assertEquals(0, completed());
            } finally { operations.shutdown(); }
        } finally { registry.close(); }
    }

    @Test @SuppressWarnings("unchecked")
    @EnabledIfEnvironmentVariable(named = "TAKEOUT_ROCKETMQ_TEST", matches = "1")
    void realMalformedMessageHasOnlyOneFailureIdentityAcrossBrokerRetries() throws Exception {
        try (var broker = new MqFixture()) {
            broker.bootstrap.createAndUpdateTopicConfig(broker.address,
                    new org.apache.rocketmq.common.TopicConfig("%RETRY%" + broker.group, 1, 1));
            var handler = new DomainEventConsumer(broker.configuration("poison"), inbox,
                    new ObjectMapper(), mock(ObjectProvider.class));
            var attempts = new CountDownLatch(2);
            var firstAttempt = new CountDownLatch(1);
            var identity = new java.util.concurrent.atomic.AtomicReference<String>();
            broker.consumer = broker.configuration("poison-consumer").newConsumer();
            broker.consumer.registerMessageListener((MessageListenerConcurrently) (messages, context) -> {
                identity.compareAndSet(null, messages.getFirst().getProperty(
                        org.apache.rocketmq.common.message.MessageConst.PROPERTY_UNIQ_CLIENT_MESSAGE_ID_KEYIDX));
                var result = handler.consumeMessage(messages, context);
                context.setDelayLevelWhenNextConsume(1); // Test-only acceleration; production retains Broker retry defaults.
                attempts.countDown();
                firstAttempt.countDown();
                return result;
            });
            broker.producer.send(new org.apache.rocketmq.common.message.Message(broker.topic, "ORDER_PAID",
                    "invalid JSON".getBytes(java.nio.charset.StandardCharsets.UTF_8)));
            broker.consumer.start();
            assertTrue(firstAttempt.await(45, TimeUnit.SECONDS), "the message must first be assigned to this new client");
            assertTrue(attempts.await(15, TimeUnit.SECONDS));
            assertNotNull(identity.get());
            assertEquals(1, inbox.failures(broker.group).count());
            assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM mq_consumer_failures WHERE consumer_group=? "
                    + "AND event_key=? AND attempts>=2", Integer.class, broker.group, DomainEventInbox.failureKey(0, identity.get())));
        }
    }

    private final class MqFixture implements AutoCloseable {
        final String topic = "takeout-reliability-" + UUID.randomUUID();
        final String group = "takeout-reliability-group-" + UUID.randomUUID();
        final String address = System.getenv().getOrDefault("TAKEOUT_ROCKETMQ_BROKER_ADDR", "127.0.0.1:10911");
        final org.apache.rocketmq.tools.admin.DefaultMQAdminExt bootstrap = configuration("bootstrap").newAdmin();
        final DefaultMQProducer producer = new DefaultMQProducer("reliability-" + UUID.randomUUID());
        org.apache.rocketmq.client.consumer.DefaultMQPushConsumer consumer;

        MqFixture() throws Exception {
            producer.setNamesrvAddr(System.getenv().getOrDefault("TAKEOUT_ROCKETMQ_NAMESRV_ADDR", "localhost:9876"));
            producer.setInstanceName(UUID.randomUUID().toString());
            producer.setVipChannelEnabled(false);
            try {
                bootstrap.start();
                bootstrap.createAndUpdateTopicConfig(address, new org.apache.rocketmq.common.TopicConfig(topic, 1, 1));
                for (String name : java.util.List.of(group, group + "-replay")) {
                    var subscription = new org.apache.rocketmq.remoting.protocol.subscription.SubscriptionGroupConfig();
                    subscription.setGroupName(name);
                    bootstrap.createAndUpdateSubscriptionGroupConfig(address, subscription);
                }
                bootstrap.updateConsumeOffset(address, group,
                        new org.apache.rocketmq.common.message.MessageQueue(topic, "takeout-broker", 0), 0);
                producer.start();
            } catch (Exception e) { close(); throw e; }
        }

        RocketMqConfiguration configuration(String tag) {
            var config = new RocketMqConfiguration() {
                @Override public org.apache.rocketmq.client.consumer.DefaultMQPushConsumer newConsumer()
                        throws org.apache.rocketmq.client.exception.MQClientException {
                    var client = super.newConsumer(); client.setInstanceName(tag + UUID.randomUUID()); return client;
                }
                @Override public org.apache.rocketmq.tools.admin.DefaultMQAdminExt newAdmin() {
                    var client = super.newAdmin(); client.setInstanceName(tag + UUID.randomUUID()); return client;
                }
                @Override public org.apache.rocketmq.client.consumer.DefaultMQPullConsumer newReplayConsumer() {
                    var client = super.newReplayConsumer(); client.setInstanceName(tag + UUID.randomUUID()); return client;
                }
            };
            ReflectionTestUtils.setField(config, "namesrvAddr", System.getenv().getOrDefault("TAKEOUT_ROCKETMQ_NAMESRV_ADDR", "localhost:9876"));
            ReflectionTestUtils.setField(config, "topic", topic);
            ReflectionTestUtils.setField(config, "consumerGroup", group);
            return config;
        }

        org.apache.rocketmq.common.message.Message envelope(String destination, long id) throws Exception {
            return new org.apache.rocketmq.common.message.Message(destination, "ORDER_PAID", "takeout-event-" + id,
                    new ObjectMapper().writeValueAsBytes(new DomainEvent(id, "ORDER_PAID", 21, "{}", "reliability")));
        }

        @Override public void close() {
            if (consumer != null) consumer.shutdown();
            producer.shutdown();
            bootstrap.shutdown();
        }
    }

    private int amount() { return jdbc.queryForObject("SELECT amount FROM mq_test_effects WHERE id=1", Integer.class); }
    private int count(String table) { return jdbc.queryForObject("SELECT COUNT(*) FROM " + table, Integer.class); }
    private int completed() {
        return jdbc.queryForObject("SELECT COUNT(*) FROM mq_consumptions WHERE consumed_at IS NOT NULL", Integer.class);
    }
}
