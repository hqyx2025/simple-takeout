package com.example.takeout.config;

import com.example.takeout.common.InstanceId;
import org.apache.rocketmq.client.consumer.DefaultMQPushConsumer;
import org.apache.rocketmq.client.consumer.DefaultMQPullConsumer;
import org.apache.rocketmq.client.exception.MQClientException;
import org.apache.rocketmq.client.producer.DefaultMQProducer;
import org.apache.rocketmq.common.consumer.ConsumeFromWhere;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.apache.rocketmq.tools.admin.DefaultMQAdminExt;

/** Remoting client: brokers stay on the private network; no Spring starter or gRPC proxy required. */
@Configuration(proxyBeanMethods = false)
public class RocketMqConfiguration {
    @Value("${takeout.mq.namesrv-addr:localhost:9876}")
    private String namesrvAddr = "localhost:9876";
    @Value("${takeout.mq.topic:takeout-domain-events}")
    private String topic = "takeout-domain-events";
    @Value("${takeout.mq.consumer-group:takeout-notifications}")
    private String consumerGroup = "takeout-notifications";

    @Bean(initMethod = "start", destroyMethod = "shutdown")
    @ConditionalOnProperty(name = "takeout.mq.enabled", havingValue = "true", matchIfMissing = true)
    DefaultMQProducer domainEventProducer() {
        var producer = new DefaultMQProducer("takeout-outbox");
        producer.setNamesrvAddr(namesrvAddr);
        producer.setInstanceName("producer-" + InstanceId.current());
        producer.setVipChannelEnabled(false);
        producer.setSendMsgTimeout(3000);
        producer.setRetryTimesWhenSendFailed(1);
        return producer;
    }

    // A failed start must be retried with a fresh client, not a client in START_FAILED state.
    public DefaultMQPushConsumer newConsumer() throws MQClientException {
        var consumer = new DefaultMQPushConsumer(consumerGroup);
        consumer.setNamesrvAddr(namesrvAddr);
        consumer.setInstanceName("consumer-" + InstanceId.current());
        consumer.setVipChannelEnabled(false);
        consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_FIRST_OFFSET);
        consumer.setConsumeMessageBatchMaxSize(1);
        consumer.setConsumeThreadMin(1);
        consumer.setConsumeThreadMax(4);
        consumer.setMaxReconsumeTimes(16);
        consumer.subscribe(topic, "*");
        return consumer;
    }

    public String topic() { return topic; }
    public String consumerGroup() { return consumerGroup; }
    public String replayGroup() { return consumerGroup + "-replay"; }

    public DefaultMQAdminExt newAdmin() {
        var admin = new DefaultMQAdminExt(3000);
        admin.setNamesrvAddr(namesrvAddr);
        admin.setInstanceName("admin-" + InstanceId.current());
        admin.setVipChannelEnabled(false);
        return admin;
    }

    public DefaultMQPullConsumer newReplayConsumer() {
        var replay = new DefaultMQPullConsumer(replayGroup());
        replay.setNamesrvAddr(namesrvAddr);
        replay.setInstanceName("replay-" + InstanceId.current());
        replay.setVipChannelEnabled(false);
        // The operations service explicitly commits broker cursors; background allocation must not cache old offsets.
        replay.setEnableRebalance(false);
        return replay;
    }
}
