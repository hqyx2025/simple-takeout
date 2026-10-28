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
        totals.putAll(db.queryForMap("SELECT COALESCE(SUM(CASE WHEN o.escrow_status=0 AND o.pay_time<>'' THEN GREATEST(o.pay_amount-COALESCE(r.amount,0),0) ELSE 0 END),0) held," +
                "COALESCE(SUM(CASE WHEN o.escrow_status=1 OR EXISTS(SELECT 1 FROM order_settlements s WHERE s.order_id=o.id) " +
                "OR EXISTS(SELECT 1 FROM refund_records r2 WHERE r2.order_id=o.id AND r2.status='REFUNDED' AND r2.settled_before=1) " +
                "THEN GREATEST(o.pay_amount-o.delivery_fee,0)-COALESCE(r.merchant_amount,0) ELSE 0 END),0) merchantSettled," +
                "COALESCE(SUM(CASE WHEN o.rider_id>0 AND o.status IN(4,6) THEN LEAST(o.delivery_fee,o.pay_amount) ELSE 0 END),0) deliveryAllocated " +
                "FROM orders o LEFT JOIN (SELECT order_id,SUM(amount) amount,SUM(merchant_amount) merchant_amount " +
                "FROM refund_records WHERE status='REFUNDED' GROUP BY order_id) r ON r.order_id=o.id WHERE o.store_id=?",storeId));
        totals.put("platformAfterSalesCost",db.queryForObject("SELECT COALESCE(SUM(r.platform_amount),0) FROM refund_records r JOIN orders o ON o.id=r.order_id WHERE o.store_id=? AND r.status='REFUNDED'",java.math.BigDecimal.class,storeId));
        totals.put("merchantDebt",db.queryForObject("SELECT COALESCE(SUM(l.debt_amount),0) FROM after_sales_ledger l JOIN orders o ON o.id=l.order_id WHERE o.store_id=?",java.math.BigDecimal.class,storeId));
        totals.put("walletCredited",db.queryForObject("SELECT COALESCE(SUM(s.wallet_credited),0) FROM order_settlements s JOIN orders o ON o.id=s.order_id WHERE o.store_id=?",java.math.BigDecimal.class,storeId));
        totals.put("debtRepaid",db.queryForObject("SELECT COALESCE(SUM(s.debt_repaid),0) FROM order_settlements s JOIN orders o ON o.id=s.order_id WHERE o.store_id=?",java.math.BigDecimal.class,storeId));
        totals.put("basis","成功收款与退款分别记账；托管扣除已退金额，商户净结算扣除售后承担；骑手送达收入保留，售后平台成本与商户待偿分列；钱包入账与抵债单独展示");
        totals.put("observedAt",java.time.Instant.now().toString());return ApiResponse.ok(totals);
    }
}
