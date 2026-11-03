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
            db.update("INSERT INTO stores(review_status,id,name,owner_id,latitude,longitude,delivery_fee,min_order,create_time) VALUES(1,10,'店铺',99,30.5,114.3,3,0,?)",now);
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
            verifyStoreReviewAndCampusFlow(http,json,db,jwt,operator,merchant,customer);
            verifyUserCrudPermissions(http,json,db,jwt,operator,merchant,
                    context.getEnvironment().getProperty("takeout.erp.integration-secret"));
        } finally {admin.execute("DROP DATABASE `"+schema+"`");}
    }
    private void verifyStoreReviewAndCampusFlow(RestClient http, ObjectMapper json, JdbcTemplate db, JwtUtil jwt,
                                                String admin, String merchant, String customer) {
        db.update("INSERT INTO categories(id,name,type) VALUES(1,'校园餐饮','PLATFORM')");
        long store=call(http,json,"POST","/api/merchant/stores",merchant,
                Map.of("name","校园入驻测试店","categoryId",1,"address","校园食堂一楼","latitude",30.5,
                        "longitude",114.3,"deliveryFee",3,"minOrder",0)).path("id").asLong();
        assertTrue(store>0);
        assertEquals(0,db.queryForObject("SELECT review_status FROM stores WHERE id=?",Integer.class,store));
        String management="/api/admin/stores/"+store;
        String owned="/api/merchant/stores/"+store;
        String detail="/api/stores/"+store;
        assertTrue(call(http,json,"GET",detail,customer,null).isNull());
        assertEquals(404,status(http,"GET",detail+"/goods",customer,null,null));
        assertEquals(403,status(http,"PUT",management+"/review",merchant,Map.of("status",1),null));
        db.update("UPDATE users SET can_update=0 WHERE id=2");
        assertEquals(403,status(http,"PUT",management+"/review",admin,Map.of("status",1),null));
        db.update("UPDATE users SET can_update=1 WHERE id=2");
        assertEquals(400,status(http,"PUT",management+"/review",admin,Map.of("status",2,"reason"," "),null));
        call(http,json,"PUT",management+"/review",admin,Map.of("status",2,"reason","请核实门牌"));
        assertEquals(2,call(http,json,"GET",management+"/reviews",admin,null).size());
        assertEquals("请核实门牌",call(http,json,"GET","/api/merchant/stores",merchant,null).get(1).path("reviewReason").asText());
        assertEquals(403,status(http,"POST",owned+"/review",customer,null,null));
        db.update("UPDATE users SET can_update=0 WHERE id=99");
        assertEquals(403,status(http,"POST",owned+"/review",merchant,null,null));
        db.update("UPDATE users SET can_update=1 WHERE id=99");
        call(http,json,"POST",owned+"/review",merchant,Map.of());
        assertEquals(409,status(http,"POST",owned+"/review",merchant,null,null));
        db.execute("CREATE TRIGGER fail_store_audit BEFORE INSERT ON store_review_records FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='injected audit failure'");
        assertEquals(500,status(http,"PUT",management+"/review",admin,Map.of("status",1),null));
        assertEquals(0,db.queryForObject("SELECT review_status FROM stores WHERE id=?",Integer.class,store));
        db.execute("DROP TRIGGER fail_store_audit");
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)) {
            var first=pool.submit(()->status(http,"PUT",management+"/review",admin,Map.of("status",1),null));
            var second=pool.submit(()->status(http,"PUT",management+"/review",admin,Map.of("status",1),null));
            var outcomes=new ArrayList<>(List.of(first.get(),second.get()));Collections.sort(outcomes);
            assertEquals(List.of(200,409),outcomes);
        } catch(Exception e) { throw new AssertionError(e); }
        assertEquals(409,status(http,"PUT",management+"/review",admin,Map.of("status",2,"reason","重复审核"),null));
        assertEquals(4,call(http,json,"GET",management+"/reviews",admin,null).size());
        assertEquals(2,call(http,json,"GET",management+"/reviews",admin,null).get(0).path("operatorId").asInt());
        long goods=call(http,json,"POST",owned+"/goods",merchant,
                Map.of("name","校园套餐","price",20,"categoryId",1,"stock",10,"status",1,
                        "image","","description","","tag","")).path("id").asLong();
        assertTrue(goods>0);
        Map<String,Object> request=Map.of("storeId",store,"addressId",20,"items",List.of(Map.of("goodsId",goods,"quantity",1)),
                "idempotencyKey","campus-review-first");
        call(http,json,"PUT",management+"/status",admin,Map.of("status",0));
        call(http,json,"PUT",owned,merchant,Map.of("status",1,"reviewStatus",1,"platformStatus",1));
        assertEquals(0,db.queryForObject("SELECT platform_status FROM stores WHERE id=?",Integer.class,store));
        assertTrue(call(http,json,"GET",detail,customer,null).isNull());
        assertEquals(400,status(http,"POST","/api/orders",customer,request,null));
        call(http,json,"PUT",owned,merchant,Map.of("status",0));
        call(http,json,"PUT",management+"/status",admin,Map.of("status",1));
        assertEquals(0,db.queryForObject("SELECT status FROM stores WHERE id=?",Integer.class,store));
        assertEquals(400,status(http,"POST","/api/orders",customer,request,null));
        call(http,json,"PUT",owned,merchant,Map.of("status",1,"deliveryFee",3));
        long order=call(http,json,"POST","/api/orders",customer,request).path("id").asLong();
        assertEquals(order,call(http,json,"POST","/api/orders",customer,request).path("id").asLong());
        String orderPath="/api/orders/"+order;
        call(http,json,"PUT",management+"/status",admin,Map.of("status",0));
        assertEquals(400,status(http,"POST",orderPath+"/pay?channel=BALANCE",customer,Map.of("paymentPassword","135790"),null));
        call(http,json,"PUT",management+"/status",admin,Map.of("status",1));
        call(http,json,"POST",orderPath+"/pay?channel=BALANCE",customer,Map.of("paymentPassword","135790"));
        call(http,json,"PUT",management+"/status",admin,Map.of("status",0));
        assertEquals(400,status(http,"PUT","/api/merchant/orders/"+order+"/accept",merchant,Map.of(),null));
        call(http,json,"PUT",management+"/status",admin,Map.of("status",1));
        call(http,json,"PUT","/api/merchant/orders/"+order+"/accept",merchant,Map.of());
        call(http,json,"PUT","/api/merchant/orders/"+order+"/ready",merchant,Map.of());
        db.update("INSERT INTO users(id,username,phone,password,role,create_time) VALUES(4,'rider','13800000004','unused',3,NOW())");
        String rider=jwt.generateToken(4,3);
        call(http,json,"PUT","/api/rider/status",rider,Map.of("online",1));
        call(http,json,"PUT","/api/rider/range/location",rider,Map.of("latitude",30.5,"longitude",114.3,"address","校园食堂"));
        call(http,json,"POST","/api/rider/orders/"+order+"/grab",rider,Map.of());
        call(http,json,"PUT","/api/rider/orders/"+order+"/pickup",rider,Map.of());
        call(http,json,"PUT","/api/rider/orders/"+order+"/deliver",rider,Map.of());
        call(http,json,"PUT",orderPath+"/confirm",customer,Map.of());
        call(http,json,"POST",orderPath+"/review",customer,
                Map.of("goodsId",goods,"rating",5,"content","送达及时","tags",List.of(),"images",List.of(),"anonymous",0));
        assertEquals(1,call(http,json,"GET",orderPath,customer,null).path("escrowStatus").asInt());
        assertEquals(1,db.queryForObject("SELECT total_orders FROM riders WHERE user_id=4",Integer.class));
        assertEquals(3.0,db.queryForObject("SELECT total_income FROM riders WHERE user_id=4",Double.class),0.001);
        assertEquals(77.0,db.queryForObject("SELECT balance FROM users WHERE id=99",Double.class),0.001);
        long cancelled=call(http,json,"POST","/api/orders",customer,Map.of("storeId",store,"addressId",20,
                "items",List.of(Map.of("goodsId",goods,"quantity",1)),"idempotencyKey","campus-review-cancel")).path("id").asLong();
        call(http,json,"PUT","/api/orders/"+cancelled+"/cancel",customer,Map.of());
        assertEquals(9,db.queryForObject("SELECT stock FROM goods WHERE id=?",Integer.class,goods));
        measureCurrentVersion(http,json,customer,store,order,db);
    }

    private void measureCurrentVersion(RestClient http,ObjectMapper json,String token,long store,long order,JdbcTemplate db) {
        List<Map<String,Object>> results=new ArrayList<>();
        for(String path:List.of("/api/stores","/api/stores/"+store,"/api/stores/"+store+"/goods","/api/orders","/api/orders/"+order)) {
            List<Double> times=new ArrayList<>();
            for(int i=0;i<30;i++) { long start=System.nanoTime();call(http,json,"GET",path,token,null);times.add((System.nanoTime()-start)/1_000_000.0); }
            Collections.sort(times);
            double p95=times.get(28);
            assertTrue(p95<2000,path+" P95="+p95);
            results.add(Map.of("path",path,"requests",30,"failures",0,"averageMs",times.stream().mapToDouble(Double::doubleValue).average().orElseThrow(),"p95Ms",p95));
        }
        String destination=System.getenv("TAKEOUT_ACCEPTANCE_OUTPUT");
        if(destination!=null) {
            try {
                var output=java.nio.file.Path.of(destination);java.nio.file.Files.createDirectories(output.getParent());
                json.writerWithDefaultPrettyPrinter().writeValue(output.toFile(),Map.of("time",LocalDateTime.now().toString(),
                        "environment",System.getProperty("os.name")+" / JDK "+System.getProperty("java.version")+" / MySQL / HTTP loopback / cache disabled / concurrency 1",
                        "stores",db.queryForObject("SELECT COUNT(*) FROM stores",Integer.class),
                        "goods",db.queryForObject("SELECT COUNT(*) FROM goods",Integer.class),"results",results,
                        "fourRoleFlow","review, balance payment, accept, ready, rider grab/pickup/deliver, confirmation, review, cancellation; existing scenario covers partial and settled refunds"));
            } catch(java.io.IOException e) { throw new java.io.UncheckedIOException(e); }
        }
    }
    private void verifyUserCrudPermissions(RestClient http,ObjectMapper json,JdbcTemplate db,JwtUtil jwt,
                                           String operator,String merchant,String integrationSecret) {
        db.update("INSERT INTO users(id,username,phone,password,role,create_time) VALUES(3,'restricted','13800000003','unused',0,'2026-11-03 00:00:00')");
        String token=jwt.generateToken(3,0);
        String endpoint="/api/admin/users/3/permissions";
        Map<String,Object> address=Map.of("name","收货人","phone","13800000003","detail","测试门牌","latitude",30.5,"longitude",114.3);
        assertEquals(200,status(http,"GET","/api/addresses",token,null,null));
        call(http,json,"PUT",endpoint,operator,Map.of("canCreate",false,"canRead",true,"canUpdate",false,"canDelete",false));
        assertEquals(403,status(http,"POST","/api/addresses",token,address,null));
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM addresses WHERE user_id=3",Integer.class));
        assertFalse(call(http,json,"GET","/api/auth/me",token,null).path("canCreate").asBoolean(true));
        db.update("UPDATE users SET can_create=1,can_read=0 WHERE id=3");
        long id=call(http,json,"POST","/api/addresses",token,address).path("id").asLong();
        assertTrue(id>0);
        assertEquals(403,status(http,"GET","/api/addresses",token,null,null));
        assertEquals(403,status(http,"PUT","/api/addresses/"+id,token,address,null));
        assertEquals(403,status(http,"DELETE","/api/addresses/"+id,token,null,null));
        assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM addresses WHERE user_id=3",Integer.class));
        Map<String,Object> cartItem=Map.of("goodsId",100,"quantity",1);
        call(http,json,"POST","/api/cart/items",token,cartItem);
        assertEquals(403,status(http,"POST","/api/cart/items",token,cartItem,null));
        assertEquals(403,status(http,"PUT","/api/cart/items/100",token,Map.of("quantity",0),null));
        assertEquals(1,db.queryForObject("SELECT quantity FROM cart_items WHERE user_id=3 AND goods_id=100",Integer.class));
        db.update("UPDATE users SET can_create=0,can_update=1 WHERE id=3");
        call(http,json,"POST","/api/cart/items",token,cartItem);
        assertEquals(2,db.queryForObject("SELECT quantity FROM cart_items WHERE user_id=3 AND goods_id=100",Integer.class));
        db.update("UPDATE users SET can_update=0,can_delete=1 WHERE id=3");
        call(http,json,"PUT","/api/cart/items/100",token,Map.of("quantity",0));
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM cart_items WHERE user_id=3",Integer.class));
        assertEquals(403,status(http,"PUT","/api/cart/items/100",token,Map.of("quantity",1),null));
        call(http,json,"PUT",endpoint,operator,Map.of("canCreate",true,"canRead",true,"canUpdate",true,"canDelete",false));
        assertTrue(call(http,json,"POST","/api/favorites/toggle?storeId=10",token,Map.of()).asBoolean());
        assertEquals(403,status(http,"POST","/api/favorites/toggle?storeId=10",token,Map.of(),null));
        assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM favorites WHERE user_id=3",Integer.class));
        call(http,json,"PUT",endpoint,operator,Map.of("canCreate",false,"canRead",true,"canUpdate",true,"canDelete",true));
        assertFalse(call(http,json,"POST","/api/favorites/toggle?storeId=10",token,Map.of()).asBoolean());
        assertEquals(403,status(http,"POST","/api/favorites/toggle?storeId=10",token,Map.of(),null));
        assertEquals(403,status(http,"PUT",endpoint,token,Map.of("canCreate",true,"canRead",true,"canUpdate",true,"canDelete",true),null));
        assertFalse(call(http,json,"GET",endpoint,operator,null).path("canCreate").asBoolean(true));
        assertEquals(403,status(http,"PUT","/api/admin/users/2/permissions",operator,
                Map.of("canCreate",false,"canRead",false,"canUpdate",false,"canDelete",false),null));
        assertEquals(400,status(http,"PUT",endpoint,operator,Map.of("canCreate",true),null));
        assertEquals(404,status(http,"GET","/api/admin/users/999999/permissions",operator,null,null));
        // ERP 的 GET 鉴权请求必须检查实际写操作，不能只检查查询权限。
        db.update("UPDATE users SET can_read=0,can_create=1 WHERE id=99");
        assertEquals(200,status(http,"GET","/api/internal/erp/context?storeId=10&operation=CREATE",merchant,null,integrationSecret));
        assertEquals(403,status(http,"GET","/api/internal/erp/context?storeId=10&operation=READ",merchant,null,integrationSecret));
        db.update("UPDATE users SET can_create=0 WHERE id=99");
        assertEquals(403,status(http,"GET","/api/internal/erp/context?storeId=10&operation=CREATE",merchant,null,integrationSecret));
        assertEquals(403,status(http,"GET","/api/internal/erp/context?storeId=10&operation=CREATE",merchant,null,null));
    }

    private int status(RestClient http,String method,String path,String token,Object body,String integrationSecret) {
        var request=http.method(org.springframework.http.HttpMethod.valueOf(method)).uri(path).header("Authorization","Bearer "+token);
        if(body!=null)request.contentType(org.springframework.http.MediaType.APPLICATION_JSON).body(body);
        if(integrationSecret!=null)request.header("X-Integration-Key",integrationSecret);
        return request.exchange((req,response)->response.getStatusCode().value());
    }

    private JsonNode call(RestClient http,ObjectMapper json,String method,String path,String token,Object body) {
        var request=http.method(org.springframework.http.HttpMethod.valueOf(method)).uri(path).header("Authorization","Bearer "+token);
        if(body!=null)request.contentType(org.springframework.http.MediaType.APPLICATION_JSON).body(body);
        JsonNode envelope=request.retrieve().body(JsonNode.class);
        assertNotNull(envelope);assertEquals(200,envelope.path("code").asInt(),path+": "+envelope.path("message").asText());
        return envelope.path("data");
    }
}
