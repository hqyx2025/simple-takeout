package com.example.takeout.erp;

import com.example.takeout.common.*;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.*;

import java.time.Duration;
import java.util.*;

@RestController
public class ErpController {
    private final ErpService service;
    private final JdbcTemplate db;
    private final RestClient app;
    private final String secret;
    public ErpController(ErpService service, JdbcTemplate db, @Value("${takeout.erp.app-uri}") String uri,
                         @Value("${takeout.erp.integration-secret}") String secret) {
        if(secret.length()<32)throw new IllegalStateException("Integration secret requires at least 32 characters");
        this.service=service;this.db=db;this.secret=secret;
        var factory=new SimpleClientHttpRequestFactory();factory.setConnectTimeout(Duration.ofMillis(500));factory.setReadTimeout(Duration.ofSeconds(2));
        this.app=RestClient.builder().baseUrl(uri).requestFactory(factory).build();
    }
    private JsonNode authority(String auth,long store,String resource) {
        if(store<=0)throw new BizException(400,"请选择门店");
        if(auth==null || !auth.startsWith("Bearer "))throw new BizException(401,"请先登录");
        try {
            var result=app.get().uri("/api/internal/erp/"+resource+"?storeId="+store)
                    .header("Authorization",auth).header("X-Integration-Key",secret).retrieve().body(JsonNode.class);
            if(result==null || result.path("code").asInt()!=200)throw new BizException(503,"门店权限服务响应异常");
            return result.path("data");
        } catch(HttpClientErrorException e){
            int code=e.getStatusCode().value();throw new BizException(code==401?401:code==403?403:400,"登录失效、门店无权访问或请求无效");
        } catch(RestClientException e){throw new BizException(503,"门店权限或经营对账服务暂不可用，请稍后重试");}
    }
    @GetMapping("/api/erp/stores/{store}/{resource}")
    public ApiResponse<?> list(@PathVariable long store,@PathVariable String resource,
            @RequestHeader(value="Authorization",required=false) String auth,
            @RequestParam(defaultValue="0") long before,@RequestParam(defaultValue="50") int limit,
            @RequestParam(required=false) Long purchaseId,@RequestParam(required=false) Long supplierId) {
        authority(auth,store,"context");
        if(resource.equals("finance"))return ApiResponse.ok(Map.of("procurement",service.finance(store),
                "operations",authority(auth,store,"finance"),"procurementBasis","按实际收货累计应付；已付为线下付款凭证登记，不扣应用钱包"));
        return ApiResponse.ok(service.list(store,resource,before,limit,purchaseId,supplierId));
    }
    @GetMapping("/api/erp/stores/{store}/purchases/{purchase}/lines")
    public ApiResponse<?> lines(@PathVariable long store,@PathVariable long purchase,@RequestHeader(value="Authorization",required=false) String auth){
        authority(auth,store,"context");return ApiResponse.ok(service.lines(store,purchase));
    }
    @PostMapping("/api/erp/stores/{store}/{action}")
    public ApiResponse<?> write(@PathVariable long store,@PathVariable String action,
            @RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="Idempotency-Key",required=false) String key,@RequestBody ErpService.Command command) {
        long actor=authority(auth,store,"context").path("userId").asLong();
        return ApiResponse.ok(service.execute(store,actor,action,key,command));
    }
    public record Event(long id,String type,long orderId,String payload) {}
    @PostMapping("/internal/events")
    public ApiResponse<?> event(@RequestHeader(value="X-Integration-Key",required=false) String key,@RequestBody Event event){
        IntegrationSecret.require(secret,key);service.event(event.id(),event.type(),event.orderId(),event.payload());return ApiResponse.ok();
    }
    @GetMapping("/health")
    public Map<String,Object> health(){db.queryForObject("SELECT 1",Integer.class);return Map.of("status","UP","service","takeout-erp");}
    @ExceptionHandler(org.springframework.dao.DuplicateKeyException.class)
    public ResponseEntity<ApiResponse<Void>> duplicate(){return ResponseEntity.status(409).body(ApiResponse.error(409,"记录、付款凭证或冲销已存在，请刷新核对"));}
}
