package com.example.takeout.service;

import com.example.takeout.common.ApiResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;
import java.time.Duration;
import java.util.Map;

/** No HTTP retry: the existing durable Outbox owns retries and ERP owns its inbox. */
@Component
public class ErpEventDelivery {
    private final RestClient client;
    private final String secret;
    private final boolean enabled;
    public ErpEventDelivery(@Value("${takeout.erp.uri:http://127.0.0.1:9200}") String uri,
            @Value("${takeout.erp.integration-secret:}") String secret,
            @Value("${takeout.erp.enabled:false}") boolean enabled,
            @Value("${takeout.mq.enabled:true}") boolean outboxEnabled) {
        this.secret=secret;this.enabled=enabled;
        if(enabled && secret.length()<32)throw new IllegalStateException("ERP integration requires a separate 32-character secret");
        if(enabled && !outboxEnabled)throw new IllegalStateException("ERP integration requires durable Outbox events");
        var factory=new SimpleClientHttpRequestFactory();factory.setConnectTimeout(Duration.ofMillis(500));factory.setReadTimeout(Duration.ofSeconds(2));
        client=RestClient.builder().baseUrl(uri).requestFactory(factory).build();
    }
    public boolean deliver(long id,String type,long orderId,String payload){
        if(!enabled)return true;
        var result=client.post().uri("/internal/events").header("X-Integration-Key",secret)
                .body(Map.of("id",id,"type",type,"orderId",orderId,"payload",payload==null?"{}":payload))
                .retrieve().body(ApiResponse.class);
        return result!=null && result.code()==200;
    }
}
