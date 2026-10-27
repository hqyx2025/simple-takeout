package com.example.takeout.controller;

import com.example.takeout.common.*;
import com.example.takeout.dao.StoreDao;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** ERP receives permissions and facts via an API; it never reads app tables. */
@RestController
@RequestMapping("/api/internal/erp")
public class ErpAuthorityController {
    private final StoreDao stores;private final JdbcTemplate db;private final String secret;
    public ErpAuthorityController(StoreDao stores,JdbcTemplate db,@Value("${takeout.erp.integration-secret:}") String secret){this.stores=stores;this.db=db;this.secret=secret;}
    private void authorize(long user,int role,long store,String key){
        IntegrationSecret.require(secret,key);
        if(role!=1 && role!=2)throw new BizException(403,"仅商户或管理端可操作采购库存");
        var found=stores.findById(store).orElseThrow(()->new BizException(404,"门店不存在"));
        if(role!=2 && found.ownerId()!=user)throw new BizException(403,"无权操作本门店");
    }
    @GetMapping("/context")
    public ApiResponse<?> context(@RequestAttribute("userId") long user,@RequestAttribute("role") int role,
            @RequestParam long storeId,@RequestHeader(value="X-Integration-Key",required=false) String key){
        authorize(user,role,storeId,key);return ApiResponse.ok(Map.of("userId",user,"role",role,"storeId",storeId));
    }
    @GetMapping("/finance")
    @Transactional(readOnly=true)
    public ApiResponse<?> finance(@RequestAttribute("userId") long user,@RequestAttribute("role") int role,
            @RequestParam long storeId,@RequestHeader(value="X-Integration-Key",required=false) String key){
        authorize(user,role,storeId,key);
        var totals=db.queryForMap("SELECT COALESCE(SUM(CASE WHEN p.type='PAY' THEN p.amount ELSE 0 END),0) receipts,"+
                "COALESCE(SUM(CASE WHEN p.type='REFUND' THEN p.amount ELSE 0 END),0) refunds " +
                "FROM orders o JOIN payment_records p ON p.order_id=o.id AND p.status='SUCCESS' WHERE o.store_id=?",storeId);
        totals.putAll(db.queryForMap("SELECT COALESCE(SUM(CASE WHEN escrow_status=0 AND pay_time<>'' THEN pay_amount ELSE 0 END),0) held,"+
                "COALESCE(SUM(CASE WHEN escrow_status=1 THEN GREATEST(pay_amount-delivery_fee,0) ELSE 0 END),0) merchantSettled,"+
                "COALESCE(SUM(CASE WHEN escrow_status=1 THEN LEAST(delivery_fee,pay_amount) ELSE 0 END),0) deliveryAllocated " +
                "FROM orders WHERE store_id=?",storeId));
        totals.put("basis","累计成功支付与退款台账；托管为已支付且未释放、未退款的款项；商户结算为已释放订单实付扣除配送费，非新增钱包余额");
        totals.put("observedAt",java.time.Instant.now().toString());return ApiResponse.ok(totals);
    }
}
