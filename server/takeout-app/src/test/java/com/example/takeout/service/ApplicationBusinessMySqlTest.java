package com.example.takeout.service;

import com.example.takeout.TakeoutApplication;
import com.example.takeout.security.JwtUtil;
import com.example.takeout.security.PaymentPasswordUtil;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.context.WebServerApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.web.client.RestClient;
import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

/** Exercises actual Spring wiring, additive migrations, HTTP authorization and transaction boundaries. */
@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST",matches="1")
class ApplicationBusinessMySqlTest {
    private String key() { byte[] bytes=new byte[32];new SecureRandom().nextBytes(bytes);return Base64.getEncoder().encodeToString(bytes); }
    @Test void firstOrderSelfDeliveryPartialRefundConfirmationAndSettledRefundRemainConsistentOverHttp() {
        String base="jdbc:mysql://"+System.getenv().getOrDefault("TAKEOUT_DB_HOST","127.0.0.1")+":"+System.getenv().getOrDefault("TAKEOUT_DB_PORT","3310")+"/";
        String opts="?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user=System.getenv().getOrDefault("TAKEOUT_DB_USERNAME","root"),password=System.getenv().getOrDefault("TAKEOUT_DB_PASSWORD","");
        String schema="takeout_http_test_"+UUID.randomUUID().toString().replace("-","");
        var admin=new JdbcTemplate(new DriverManagerDataSource(base+opts,user,password));
        admin.execute("CREATE DATABASE `"+schema+"`");
        try (var context=new SpringApplicationBuilder(TakeoutApplication.class).run(
                "--server.port=0","--server.address=127.0.0.1","--spring.profiles.active=test",
                "--spring.datasource.url="+base+schema+opts,"--spring.datasource.username="+user,"--spring.datasource.password="+password,
                "--spring.datasource.hikari.maximum-pool-size=2","--spring.datasource.hikari.minimum-idle=0",
                "--takeout.jwt.secret="+key(),"--takeout.sms.hmac-secret="+key(),
                "--takeout.assistant.encryption-secret="+key(),"--takeout.wallet.encryption-secret="+key(),
                "--takeout.erp.integration-secret="+key(),"--takeout.payment.sandbox=false","--takeout.payment.real-enabled=false",
                "--takeout.sms.qq.smtp-host=127.0.0.1","--takeout.sms.qq.smtp-port=1",
                "--takeout.sms.qq.username=isolated-test@example.invalid","--takeout.sms.qq.auth-code=local-test-only",
                "--takeout.data-seed.enabled=false","--takeout.mq.enabled=false","--takeout.cache.enabled=false",
                "--takeout.security.rate-limit.enabled=true","--spring.data.redis.timeout=25ms",
                "--spring.data.redis.connect-timeout=25ms","--spring.data.redis.lettuce.pool.min-idle=0",
                "--takeout.upload.dir=../../TemporaryCacheStorage/business-http-uploads")) {
            JdbcTemplate db=context.getBean(JdbcTemplate.class);
            String now=LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
            db.update("INSERT INTO users(id,username,phone,password,role,balance,create_time,payment_password_hash) VALUES(1,'customer','13800000001','unused',0,200,?,?)",now,PaymentPasswordUtil.hash("135790"));
            db.update("INSERT INTO users(id,username,phone,password,role,balance,create_time) VALUES(2,'admin','13800000002','unused',2,0,?),(99,'merchant','13800000099','unused',1,0,?)",now,now);
            db.update("INSERT INTO stores(id,name,owner_id,latitude,longitude,delivery_fee,min_order,create_time) VALUES(10,'店铺',99,30.5,114.3,3,0,?)",now);
            db.update("INSERT INTO goods(id,store_id,name,price,stock,create_time) VALUES(100,10,'餐品',100,10,?)",now);
            db.update("INSERT INTO addresses(id,user_id,name,phone,detail,latitude,longitude,create_time) VALUES(20,1,'收货人','13800000001','测试门牌',30.5,114.3,?)",now);
            String start=LocalDateTime.now().minusDays(1).format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
            String end=LocalDateTime.now().plusDays(1).format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
            db.update("INSERT INTO marketing_activities(store_id,type,title,discount_rate,reduce_amount,start_time,end_time,status,create_time) VALUES(10,'DISCOUNT','九折',0.9,0,?,?,1,?),(10,'DISCOUNT','八折',0.8,0,?,?,1,?),(10,'NEW_USER','本店首单',0,3,?,?,1,?)",start,end,now,start,end,now,start,end,now);
            JwtUtil jwt=context.getBean(JwtUtil.class);
            String customer=jwt.generateToken(1,0),merchant=jwt.generateToken(99,1),operator=jwt.generateToken(2,2);
            int port=((WebServerApplicationContext)context).getWebServer().getPort();
            RestClient http=RestClient.create("http://127.0.0.1:"+port);
            ObjectMapper json=context.getBean(ObjectMapper.class);
            assertEquals("MERCHANT",call(http,json,"PUT","/api/merchant/stores/10/fulfillment",merchant,Map.of("mode","MERCHANT")).path("mode").asText());
            Map<String,Object> request=Map.of("storeId",10,"addressId",20,"items",List.of(Map.of("goodsId",100,"quantity",1,"price",1)),
                    "idempotencyKey","http-first-order-stable-key","deliveryType","DELIVERY");
            JsonNode created=call(http,json,"POST","/api/orders",customer,request);
            long id=created.path("id").asLong();assertTrue(id>0);assertEquals(0,created.path("status").asInt());
            assertEquals(80.0,created.path("payAmount").asDouble(),0.001);
            assertEquals("MERCHANT",created.path("capabilities").path("fulfillmentMode").asText());
            assertEquals(id,call(http,json,"POST","/api/orders",customer,request).path("id").asLong());
            call(http,json,"POST","/api/orders/"+id+"/pay?channel=BALANCE",customer,Map.of("paymentPassword","135790"));
            for(String action:List.of("accept","ready","deliver","complete")) call(http,json,"PUT","/api/merchant/orders/"+id+"/"+action,merchant,Map.of());
            JsonNode first=call(http,json,"POST","/api/orders/"+id+"/refund",customer,Map.of("reasonType","OTHER","reason","少送餐品","amount",10,"idempotencyKey","http-first-refund-stable-key"));
            call(http,json,"POST","/api/admin/refunds/"+first.path("id").asLong()+"/approve",operator,Map.of());
            call(http,json,"PUT","/api/orders/"+id+"/confirm",customer,Map.of());
            assertEquals(67.0,db.queryForObject("SELECT balance FROM users WHERE id=99",Double.class),0.001);
            JsonNode second=call(http,json,"POST","/api/orders/"+id+"/refund",customer,Map.of("reasonType","OTHER","reason","补充核实","amount",10,"idempotencyKey","http-second-refund-stable-key"));
            call(http,json,"POST","/api/admin/refunds/"+second.path("id").asLong()+"/approve",operator,Map.of());
            assertEquals(140.0,db.queryForObject("SELECT balance FROM users WHERE id=1",Double.class),0.001);
            assertEquals(57.0,db.queryForObject("SELECT balance FROM users WHERE id=99",Double.class),0.001);
            assertEquals(9,db.queryForObject("SELECT stock FROM goods WHERE id=100",Integer.class));
            assertEquals("USED",db.queryForObject("SELECT state FROM promotion_claims WHERE user_id=1 AND store_id=10",String.class));
            assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM order_settlements WHERE order_id=?",Integer.class,id));
            JsonNode detail=call(http,json,"GET","/api/orders/"+id,customer,null);
            assertEquals(4,detail.path("status").asInt());assertEquals(1,detail.path("escrowStatus").asInt());
            assertEquals(60.0,detail.path("capabilities").path("refundRemaining").asDouble(),0.001);
            assertEquals(57.0,call(http,json,"GET","/api/merchant/stats?storeId=10",merchant,null).path("todayIncome").asDouble(),0.001);
            var forbidden=http.post().uri("/api/orders").header("Authorization","Bearer "+merchant).contentType(org.springframework.http.MediaType.APPLICATION_JSON).body(request)
                    .exchange((req,response)->response.getStatusCode().value());
            assertEquals(403,forbidden);
        } finally {admin.execute("DROP DATABASE `"+schema+"`");}
    }
    private JsonNode call(RestClient http,ObjectMapper json,String method,String path,String token,Object body) {
        var request=http.method(org.springframework.http.HttpMethod.valueOf(method)).uri(path).header("Authorization","Bearer "+token);
        if(body!=null)request.contentType(org.springframework.http.MediaType.APPLICATION_JSON).body(body);
        JsonNode envelope=request.retrieve().body(JsonNode.class);
        assertNotNull(envelope);assertEquals(200,envelope.path("code").asInt(),path+": "+envelope.path("message").asText());
        return envelope.path("data");
    }
}
