package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.RiderDao;
import com.example.takeout.model.Order;
import com.example.takeout.model.OrderCapabilities;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Delivery mode snapshots, role-specific actions, and durable operational exception handling. */
@Service
public class OrderOperationsService {
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    public record DeliveryIssue(long id, long orderId, String type, String note, String status,
                                int reporterRole, String createTime, String resolveNote) {}
    public record IssuePage(List<DeliveryIssue> list, int total, int page, int pageSize, boolean hasMore) {}
    private final JdbcTemplate db;
    private final OrderDao orders;
    private final StoreDao stores;
    private final RiderDao riders;
    private final ObjectProvider<OrderService> orderService;
    private final ObjectProvider<AfterSalesService> afterSales;
    public OrderOperationsService(JdbcTemplate db, OrderDao orders, StoreDao stores, RiderDao riders,
                                  ObjectProvider<OrderService> orderService, ObjectProvider<AfterSalesService> afterSales) {
        this.db=db; this.orders=orders; this.stores=stores; this.riders=riders;
        this.orderService=orderService; this.afterSales=afterSales;
    }
    public String storeMode(long store) {
        return db.query("SELECT mode FROM store_fulfillment WHERE store_id=?",(rs,n)->rs.getString(1),store).stream().findFirst().orElse("RIDER");
    }
    public String mode(long order) {
        return db.query("SELECT mode FROM order_fulfillment WHERE order_id=?",(rs,n)->rs.getString(1),order).stream().findFirst().orElse("RIDER");
    }
    public void snapshot(long order, long store) {
        db.update("INSERT INTO order_fulfillment(order_id,mode) VALUES(?,?)",order,storeMode(store));
    }
    public Map<String,String> readStoreMode(long user,int role,long store) {
        if(role!=2 && (role!=1 || !stores.hasMerchantAccess(user,store))) throw new BizException(403,"无权查看门店配送方式");
        return Map.of("mode",storeMode(store));
    }
    @Transactional
    public Map<String,String> setStoreMode(long user,int role,long store,String mode) {
        var found=stores.findById(store).orElseThrow(()->new BizException(404,"门店不存在"));
        if(role!=2 && (role!=1 || found.ownerId()!=user)) throw new BizException(403,"仅店主或平台可设置配送方式");
        if(!Set.of("RIDER","MERCHANT").contains(mode==null?"":mode)) throw new BizException("配送方式无效");
        db.update("INSERT INTO store_fulfillment(store_id,mode) VALUES(?,?) ON DUPLICATE KEY UPDATE mode=VALUES(mode)",store,mode);
        return Map.of("mode",mode);
    }
    public OrderCapabilities capabilities(Order order,String readyTime,int role) {
        String mode=mode(order.id());
        long rider=orders.findRiderId(order.id());
        AfterSalesService sales=afterSales.getObject();
        BigDecimal remaining=role==0 && order.status()!=0 && order.status()!=5 && order.escrowStatus()!=2
                ? sales.remainingRefund(order) : BigDecimal.ZERO;
        LocalDateTime deadline=role==0 ? sales.eligibleUntil(order) : null;
        var actions=new ArrayList<String>();
        if(role==0) {
            if(order.status()==0) actions.add("PAY");
            if(order.status()==0 || order.status()==1) actions.add("CANCEL");
            if(order.status()==4 && order.escrowStatus()==0) actions.add("CONFIRM");
            if(sales.canApply(order)) actions.add("REFUND");
            if(order.status()==4 && order.escrowStatus()==1 && order.reviewed()!=1) actions.add("REVIEW");
        }
        if(role==1 || role==2) {
            if(order.status()==1) {
                actions.add("MERCHANT_ACCEPT");
                if(role==1) actions.add("MERCHANT_REJECT");
            }
            if(order.status()==2 && (readyTime==null || readyTime.isBlank())) actions.add("MERCHANT_READY");
            if("MERCHANT".equals(mode) && rider==0) {
                if(order.status()==2 && readyTime!=null && !readyTime.isBlank()) actions.add("MERCHANT_DELIVER");
                if(order.status()==3) actions.add("MERCHANT_COMPLETE");
            }
            if(role==2 && order.status()>=0 && order.status()<=3) actions.add("CANCEL");
        }
        if(role==3 && "RIDER".equals(mode)) {
            if(order.status()==2 && readyTime!=null && !readyTime.isBlank()) actions.add(rider==0?"RIDER_GRAB":"RIDER_PICKUP");
            if(order.status()==3 && rider>0) actions.add("RIDER_DELIVER");
        }
        if(order.status()>=1 && order.status()<=3) actions.add("REPORT_ISSUE");
        return new OrderCapabilities(actions,remaining.doubleValue(),deadline==null?"":deadline.format(TIME),mode);
    }
    public void requireMode(long order,String expected) {
        if(!expected.equals(mode(order))) throw new BizException("订单配送方式不支持该操作");
    }
    private void authorize(long user,int role,Order order) {
        boolean allowed=role==2 || role==0 && order.userId()==user || role==1 && stores.hasMerchantAccess(user,order.storeId());
        if(role==3) {
            var rider=riders.findByUserId(user).orElseThrow(()->new BizException(403,"骑手身份无效"));
            allowed=orders.findRiderId(order.id())==rider.id();
        }
        if(!allowed) throw new BizException(403,"无权查看或上报本订单异常");
    }
    private DeliveryIssue map(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new DeliveryIssue(rs.getLong("id"),rs.getLong("order_id"),rs.getString("type"),rs.getString("note"),
                rs.getString("status"),rs.getInt("reporter_role"),rs.getString("create_time"),rs.getString("resolve_note"));
    }
    public List<DeliveryIssue> issues(long user,int role,long orderId) {
        Order order=orders.findById(orderId).orElseThrow(()->new BizException(404,"订单不存在"));
        authorize(user,role,order);
        return db.query("SELECT * FROM delivery_issues WHERE order_id=? ORDER BY id DESC",(rs,n)->map(rs),orderId);
    }
    @Transactional
    public DeliveryIssue report(long user,int role,long orderId,String type,String note,String key) {
        Order order=orders.findByIdForUpdate(orderId).orElseThrow(()->new BizException(404,"订单不存在"));
        authorize(user,role,order);
        if(key==null || !key.matches("[A-Za-z0-9_-]{16,128}")) throw new BizException("请提供有效请求号");
        if(!Set.of("NO_RIDER","CUSTOMER_UNREACHABLE","ADDRESS_PROBLEM","FOOD_DAMAGED","OTHER").contains(type==null?"":type)) throw new BizException("异常类型无效");
        String safe=note==null?"":note.trim();
        if(safe.isBlank() || safe.length()>500) throw new BizException("请填写500字以内异常说明");
        var replay=db.query("SELECT * FROM delivery_issues WHERE order_id=? AND reporter_id=? AND request_key=?",(rs,n)->map(rs),orderId,user,key);
        if(!replay.isEmpty()) {
            DeliveryIssue previous=replay.getFirst();
            if(!type.equals(previous.type()) || !safe.equals(previous.note())) throw new BizException(409,"请求号已用于其他上报");
            return previous;
        }
        if(order.status()<1 || order.status()>3) throw new BizException("仅履约中的订单可上报配送异常");
        db.update("INSERT INTO delivery_issues(order_id,reporter_id,reporter_role,request_key,type,note) VALUES(?,?,?,?,?,?)",orderId,user,role,key,type,safe);
        return db.query("SELECT * FROM delivery_issues WHERE order_id=? AND reporter_id=? AND request_key=?",(rs,n)->map(rs),orderId,user,key).getFirst();
    }
    public IssuePage adminIssues(String status,int page,int pageSize) {
        String filter=status==null || status.isBlank()?"OPEN":status;
        if(!Set.of("OPEN","RESOLVED","ALL").contains(filter)) throw new BizException("异常状态无效");
        int size=Math.clamp(pageSize,1,100),current=Math.max(page,1);
        String where="ALL".equals(filter)?"1=1":"status='"+filter+"'";
        Integer total=db.queryForObject("SELECT COUNT(*) FROM delivery_issues WHERE "+where,Integer.class);
        var list=db.query("SELECT * FROM delivery_issues WHERE "+where+" ORDER BY id DESC LIMIT ? OFFSET ?",(rs,n)->map(rs),size,(long)(current-1)*size);
        int count=total==null?0:total;
        return new IssuePage(list,count,current,size,(long)current*size<count);
    }
    @Transactional
    public DeliveryIssue resolve(long admin,long issueId,String action,String note) {
        String safe=note==null?"":note.trim();
        if(safe.isBlank() || safe.length()>500) throw new BizException("请填写500字以内处理说明");
        if(!Set.of("REASSIGN","RESUME","CANCEL").contains(action==null?"":action)) throw new BizException("处理动作无效");
        var initial=db.queryForList("SELECT order_id FROM delivery_issues WHERE id=?",issueId);
        if(initial.isEmpty()) throw new BizException(404,"异常记录不存在");
        long orderId=((Number)initial.getFirst().get("order_id")).longValue();
        Order order=orders.findByIdForUpdate(orderId).orElseThrow(()->new BizException(404,"订单不存在"));
        DeliveryIssue issue=db.query("SELECT * FROM delivery_issues WHERE id=? FOR UPDATE",(rs,n)->map(rs),issueId).getFirst();
        if("RESOLVED".equals(issue.status())) return issue;
        if("REASSIGN".equals(action)) {
            requireMode(orderId,"RIDER");
            if(order.status()!=2) throw new BizException("仅取餐前允许改派，取餐后请核实并选择继续或取消");
            db.update("UPDATE orders SET rider_id=0 WHERE id=? AND status=2",orderId);
        } else if("CANCEL".equals(action)) {
            orderService.getObject().cancelOrderByAdmin(orderId);
        }
        db.update("UPDATE delivery_issues SET status='RESOLVED',resolve_time=NOW(),resolve_note=?,resolver_id=?,resolution=? WHERE id=? AND status='OPEN'",safe,admin,action,issueId);
        return db.query("SELECT * FROM delivery_issues WHERE id=?",(rs,n)->map(rs),issueId).getFirst();
    }
}
