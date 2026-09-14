package com.example.takeout.config;

import io.lettuce.core.ClientOptions;
import io.lettuce.core.SocketOptions;
import io.lettuce.core.TimeoutOptions;
import io.lettuce.core.cluster.ClusterClientOptions;
import io.lettuce.core.resource.ClientResources;
import io.lettuce.core.resource.DefaultClientResources;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.data.redis.LettuceClientConfigurationBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;

import java.time.Duration;

/**
 * Redis 缓存配置。
 *
 * <p>缓存统一使用字符串模板 + JSON 序列化：比默认的 JDK 序列化可读、跨版本稳定，
 * 也避免缓存内容随类结构变更而无法反序列化。Redis 不可用时相关 Bean 仍然创建，
 * 由 {@code HotDataCacheService} 在调用处降级回源数据库。</p>
 *
 * <p>缓存不注册 Spring Cache 注解，热点键的失效范围需要按业务语义精确控制
 * （例如菜品变更要同时清掉该店商品、榜单与秒杀缓存），显式失效比注解更可控。</p>
 */
@Configuration
public class RedisConfig {

    @Bean
    @ConditionalOnMissingBean(StringRedisTemplate.class)
    public StringRedisTemplate stringRedisTemplate(RedisConnectionFactory connectionFactory) {
        StringRedisTemplate template = new StringRedisTemplate(connectionFactory);
        template.setEnableTransactionSupport(false);
        return template;
    }

    /** 缓存专用 ObjectMapper：独立于 Web 层，避免 Web 序列化配置变更影响已写入的缓存内容。 */
    @Bean("cacheObjectMapper")
    public com.fasterxml.jackson.databind.ObjectMapper cacheObjectMapper() {
        com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
        mapper.registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule());
        mapper.disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
        mapper.disable(com.fasterxml.jackson.databind.SerializationFeature.FAIL_ON_EMPTY_BEANS);
        mapper.configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        return mapper;
    }

    /**
     * Redis 故障时的快速失败：关闭命令自动重试并收紧连接超时。
     * 缓存是可选加速层，Redis 宕机时必须尽快回源数据库，
     * 不能让默认的多次重试把单个请求拖到数秒。
     */
    @Bean
    public LettuceClientConfigurationBuilderCustomizer cacheFailFastCustomizer(
            @Value("${spring.data.redis.connect-timeout:500ms}") Duration connectTimeout,
            @Value("${spring.data.redis.timeout:500ms}") Duration commandTimeout) {
        return builder -> builder
                .clientOptions(ClientOptions.builder()
                        .autoReconnect(false)
                        .disconnectedBehavior(ClientOptions.DisconnectedBehavior.REJECT_COMMANDS)
                        .timeoutOptions(TimeoutOptions.enabled(commandTimeout))
                        .socketOptions(SocketOptions.builder()
                                .connectTimeout(connectTimeout)
                                .build())
                        .build())
                .commandTimeout(commandTimeout);
    }

    /** 共享客户端资源：避免连接池重建时泄漏线程与 Netty 资源。 */
    @Bean(destroyMethod = "shutdown")
    @ConditionalOnMissingBean(ClientResources.class)
    public ClientResources clientResources() {
        return DefaultClientResources.create();
    }
}

