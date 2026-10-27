package com.example.takeout.erp;

import com.example.takeout.common.BizException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** Procurement owns only operating supplies, never sellable dishes or ingredient recipes. */
@Service
public class ErpService {
    public record Line(Long materialId, BigDecimal quantity, BigDecimal unitPrice, String purchaseUnit, BigDecimal factor) {}
    public record Command(Long id, Long supplierId, Long materialId, String name, String contact, String unit,
                          Boolean enabled, List<Line> lines, BigDecimal quantity, BigDecimal amount,
                          String reference, String kind, String reason, Boolean approve) {}
    private final JdbcTemplate db;
    private final TransactionTemplate tx;
    private final ObjectMapper json;

    public ErpService(JdbcTemplate db, TransactionTemplate tx, ObjectMapper json) {
        this.db = db; this.tx = tx; this.json = json;
    }

    public Map<String, Object> execute(long store, long actor, String action, String key, Command c) {
        check(key != null && key.matches("[A-Za-z0-9_-]{16,128}"), "请提供有效的幂等请求号");
        check(c != null, "操作内容不能为空");
        String hash = hash(actor + ":" + action + ":" + encode(c));
        return tx.execute(status -> {
            // A unique row and its lock serialize retries across all ERP instances, in the business transaction.
            db.update("INSERT INTO erp_requests(store_id,request_key,request_hash) VALUES(?,?,?) " +
                    "ON DUPLICATE KEY UPDATE request_key=request_key", store, key, hash);
            var request = db.queryForMap("SELECT * FROM erp_requests WHERE store_id=? AND request_key=? FOR UPDATE", store, key);
            check(hash.equals(request.get("request_hash")), "请求号已用于其他操作，请勿修改后重放");
            if (request.get("result_json") != null) return decode(request.get("result_json").toString());
            long id = mutate(store, actor, action, c);
            db.update("INSERT INTO erp_audit(store_id,operator_id,action,document_id,detail) VALUES(?,?,?,?,?)",
                    store, actor, action, id, c.reason() == null ? "" : text(c.reason(), 255));
            Map<String, Object> result = Map.of("id", id);
            db.update("UPDATE erp_requests SET result_json=? WHERE store_id=? AND request_key=?", encode(result), store, key);
            return result;
        });
    }

    private long mutate(long s, long actor, String action, Command c) {
        switch (action) {
            case "suppliers", "supplier-update" -> {
                if(action.equals("supplier-update")) {
                    owned("erp_suppliers",s,c.id());
                    db.update("UPDATE erp_suppliers SET name=?,contact=? WHERE id=? AND store_id=?",text(c.name(),100),text(c.contact(),100),c.id(),s);
                    return c.id();
                }
                db.update("INSERT INTO erp_suppliers(store_id,name,contact) VALUES(?,?,?)", s, text(c.name(),100),text(c.contact(),100));
                return lastId();
            }
            case "supplier-status" -> {
                check(c.enabled()!=null,"请选择启停状态");
                owned("erp_suppliers",s,c.id());
                db.update("UPDATE erp_suppliers SET enabled=? WHERE id=? AND store_id=?",c.enabled(),c.id(),s);
                return c.id();
            }
            case "materials" -> {
                db.update("INSERT INTO erp_materials(store_id,name,unit) VALUES(?,?,?)",s,text(c.name(),100),text(c.unit(),16));
                return lastId();
            }
            case "purchases" -> {
                var supplier=owned("erp_suppliers",s,c.supplierId());
                check(Boolean.TRUE.equals(supplier.get("enabled")),"供应商已停用");
                check(c.lines()!=null && !c.lines().isEmpty() && c.lines().size()<=50,"采购明细须为1至50项");
                db.update("INSERT INTO erp_purchases(store_id,supplier_id,operator_id) VALUES(?,?,?)",s,c.supplierId(),actor);
                long p=lastId(); var seen=new HashSet<Long>(); BigDecimal total=BigDecimal.ZERO;
                for (Line line:c.lines()) {
                    check(line!=null && line.materialId()!=null && seen.add(line.materialId()),"物料重复或无效");
                    var material=owned("erp_materials",s,line.materialId());
                    BigDecimal qty=positive(line.quantity(),3),price=positive(line.unitPrice(),4),factor=positive(line.factor(),3);
                    String unit=text(line.purchaseUnit(),16);
                    if(unit.equals(material.get("unit"))) check(factor.compareTo(BigDecimal.ONE)==0,"相同单位换算率必须为1");
                    quantity(qty.multiply(factor));
                    total=total.add(money(qty.multiply(price)));
                    db.update("INSERT INTO erp_purchase_lines(purchase_id,material_id,quantity,unit_price,purchase_unit,factor) VALUES(?,?,?,?,?,?)",
                            p,line.materialId(),qty,price,unit,factor);
                }
                bounded(total);
                db.update("UPDATE erp_purchases SET ordered_amount=? WHERE id=?",total,p);
                return p;
            }
            case "submit", "confirm", "close" -> {
                var p=owned("erp_purchases",s,c.id()); String current=p.get("status").toString(); String target;
                if(action.equals("submit")) { check(current.equals("DRAFT"),"仅草稿可提交");target="SUBMITTED"; }
                else if(action.equals("confirm")) {
                    check(current.equals("SUBMITTED"),"仅已提交采购单可确认");
                    check(Boolean.TRUE.equals(owned("erp_suppliers",s,num(p,"supplier_id")).get("enabled")),"供应商已停用");target="CONFIRMED";
                } else { check(Set.of("DRAFT","SUBMITTED","CONFIRMED").contains(current),"采购单已关闭");target="CLOSED"; }
                db.update("UPDATE erp_purchases SET status=? WHERE id=? AND store_id=?",target,c.id(),s);return c.id();
            }
            case "receive" -> { return receive(s,actor,c); }
            case "reverse-receipt" -> { return reverseReceipt(s,actor,c); }
            case "adjust" -> {
                check(Set.of("COUNT","LOSS").contains(c.kind()==null?"":c.kind()),"请选择盘点或报损");
                var m=owned("erp_materials",s,c.materialId()); BigDecimal book=decimal(m,"balance"),actual;
                if(c.kind().equals("LOSS")) actual=book.subtract(positive(c.quantity(),3)); else actual=quantity(c.quantity());
                check(actual.signum()>=0 && book.compareTo(actual)!=0,"调整数量无效或无差异");
                db.update("INSERT INTO erp_adjustments(store_id,material_id,kind,book_qty,actual_qty,reason,operator_id) VALUES(?,?,?,?,?,?,?)",
                        s,c.materialId(),c.kind(),book,actual,text(c.reason(),255),actor); return lastId();
            }
            case "review" -> {
                var a=owned("erp_adjustments",s,c.id());check(a.get("status").equals("SUBMITTED"),"调整单已审核");
                check(c.approve()!=null,"请选择审核结果");
                check(num(a,"operator_id")!=actor,"制单人与审核人不能为同一账号");
                if(c.approve()) {
                    var m=owned("erp_materials",s,num(a,"material_id"));
                    check(decimal(m,"balance").compareTo(decimal(a,"book_qty"))==0,"库存已变化，请拒绝后重新盘点");
                    change(s,actor,m,"ADJUST",c.id(),decimal(a,"actual_qty").subtract(decimal(a,"book_qty")),a.get("reason").toString(),null);
                }
                db.update("UPDATE erp_adjustments SET status=?,reviewer_id=? WHERE id=?",c.approve()?"APPROVED":"REJECTED",actor,c.id());
                return c.id();
            }
            case "reverse" -> {
                var l=owned("erp_ledger",s,c.id()); check(l.get("source_type").equals("ADJUST"),"收货请使用整单冲销，冲销记录不可再次冲销");
                var m=owned("erp_materials",s,num(l,"material_id"));
                change(s,actor,m,"REVERSAL",c.id(),decimal(l,"delta").negate(),text(c.reason(),255),c.id());return c.id();
            }
            case "pay" -> {
                var p=owned("erp_purchases",s,c.id()); BigDecimal amount=positive(c.amount(),2);
                check(decimal(p,"paid").add(amount).compareTo(decimal(p,"payable"))<=0,"付款不能超过已收货应付余额");
                db.update("INSERT INTO erp_payments(store_id,purchase_id,amount,reference,operator_id) VALUES(?,?,?,?,?)",
                        s,c.id(),amount,text(c.reference(),100),actor);
                long id=lastId();db.update("UPDATE erp_purchases SET paid=paid+? WHERE id=?",amount,c.id());return id;
            }
            default -> throw new BizException(404,"操作不存在");
        }
    }

    private long receive(long s,long actor,Command c) {
        var p=owned("erp_purchases",s,c.id());check(p.get("status").equals("CONFIRMED"),"仅已确认采购单可收货");
        check(c.lines()!=null && !c.lines().isEmpty() && c.lines().size()<=50,"收货明细须为1至50项");
        db.update("INSERT INTO erp_receipts(store_id,purchase_id,operator_id) VALUES(?,?,?)",s,c.id(),actor);long receipt=lastId();
        BigDecimal payable=decimal(p,"payable"); var seen=new HashSet<Long>();
        var lines=new ArrayList<>(c.lines());check(lines.stream().allMatch(l->l!=null && l.materialId()!=null),"收货物料无效");
        lines.sort(Comparator.comparing(Line::materialId));
        for(Line line:lines) {
            check(seen.add(line.materialId()),"收货物料重复");
            var rows=db.queryForList("SELECT * FROM erp_purchase_lines WHERE purchase_id=? AND material_id=? FOR UPDATE",c.id(),line.materialId());
            check(!rows.isEmpty(),"物料不在该采购单内");var l=rows.getFirst();BigDecimal qty=positive(line.quantity(),3),old=decimal(l,"received"),next=old.add(qty);
            check(next.compareTo(decimal(l,"quantity"))<=0,"收货超过采购数量");
            var material=owned("erp_materials",s,line.materialId());
            change(s,actor,material,"RECEIPT",receipt,quantity(qty.multiply(decimal(l,"factor"))),"采购收货",null);
            payable=payable.add(money(next.multiply(decimal(l,"unit_price"))).subtract(money(old.multiply(decimal(l,"unit_price")))));
            db.update("UPDATE erp_purchase_lines SET received=? WHERE id=?",next,l.get("id"));
        }
        bounded(payable);db.update("UPDATE erp_purchases SET payable=? WHERE id=?",payable,c.id());return receipt;
    }

    private long reverseReceipt(long s,long actor,Command c) {
        // Lock purchase before receipt/material, the same order as receiving and paying.
        var found=db.queryForList("SELECT * FROM erp_receipts WHERE id=? AND store_id=?",c.id(),s);check(!found.isEmpty(),"收货单不存在");
        long purchase=num(found.getFirst(),"purchase_id");var p=owned("erp_purchases",s,purchase);
        check(db.queryForObject("SELECT COUNT(*) FROM erp_receipt_reversals WHERE receipt_id=?",Integer.class,c.id())==0,"收货单已冲销");
        var ledgers=db.queryForList("SELECT * FROM erp_ledger WHERE source_type='RECEIPT' AND source_id=? AND store_id=? ORDER BY material_id",c.id(),s);
        BigDecimal payable=decimal(p,"payable");String reason=text(c.reason(),255);
        for(var l:ledgers) {
            var line=db.queryForMap("SELECT * FROM erp_purchase_lines WHERE purchase_id=? AND material_id=? FOR UPDATE",purchase,l.get("material_id"));
            BigDecimal old=decimal(line,"received"),qty=decimal(l,"delta").divide(decimal(line,"factor"),3,RoundingMode.UNNECESSARY),next=old.subtract(qty);
            check(next.signum()>=0,"收货数量冲突");
            payable=payable.add(money(next.multiply(decimal(line,"unit_price"))).subtract(money(old.multiply(decimal(line,"unit_price")))));
            var m=owned("erp_materials",s,num(l,"material_id"));
            change(s,actor,m,"REVERSAL",num(l,"id"),decimal(l,"delta").negate(),reason,num(l,"id"));
            db.update("UPDATE erp_purchase_lines SET received=? WHERE id=?",next,line.get("id"));
        }
        check(payable.compareTo(decimal(p,"paid"))>=0,"该收货已有付款，请先核对供应商退款，不能冲减已付款应付");
        db.update("UPDATE erp_purchases SET payable=? WHERE id=?",payable,purchase);
        db.update("INSERT INTO erp_receipt_reversals(receipt_id,store_id,operator_id,reason) VALUES(?,?,?,?)",c.id(),s,actor,reason);return c.id();
    }

    private void change(long s,long actor,Map<String,Object> material,String source,long sourceId,BigDecimal delta,String reason,Long reversal) {
        BigDecimal before=decimal(material,"balance"),after=quantity(before.add(delta));check(after.signum()>=0,"库存不足，无法调整或冲销");
        db.update("UPDATE erp_materials SET balance=? WHERE id=? AND store_id=?",after,material.get("id"),s);
        db.update("INSERT INTO erp_ledger(store_id,material_id,source_type,source_id,delta,before_qty,after_qty,unit,reason,operator_id,reversal_of) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                s,material.get("id"),source,sourceId,delta,before,after,material.get("unit"),reason,actor,reversal);
    }

    public List<Map<String,Object>> list(long s,String resource,long before,int limit,Long purchase,Long supplier) {
        String table=switch(resource) {
            case "suppliers"->"erp_suppliers";case "materials"->"erp_materials";case "purchases"->"erp_purchases";
            case "receipts"->"erp_receipts";case "ledger"->"erp_ledger";case "adjustments"->"erp_adjustments";
            case "payments"->"erp_payments";case "audit"->"erp_audit"; default->throw new BizException(404,"资源不存在");};
        String filter=""; var args=new ArrayList<Object>();args.add(s);args.add(before<=0?Long.MAX_VALUE:before);
        if(purchase!=null && Set.of("receipts","payments").contains(resource)){filter+=" AND purchase_id=?";args.add(purchase);}
        if(supplier!=null && resource.equals("purchases")){filter+=" AND supplier_id=?";args.add(supplier);}
        args.add(Math.max(1,Math.min(limit,100)));
        return db.queryForList("SELECT * FROM "+table+" WHERE store_id=? AND id<?"+filter+" ORDER BY id DESC LIMIT ?",args.toArray());
    }
    public List<Map<String,Object>> lines(long s,long purchase) {
        check(!db.queryForList("SELECT id FROM erp_purchases WHERE id=? AND store_id=?",purchase,s).isEmpty(),"采购单不存在");
        return db.queryForList("SELECT l.*,m.name,m.unit FROM erp_purchase_lines l JOIN erp_materials m ON m.id=l.material_id WHERE l.purchase_id=? AND m.store_id=? ORDER BY l.id",purchase,s);
    }
    public Map<String,Object> finance(long s) {
        return db.queryForMap("SELECT COALESCE(SUM(ordered_amount),0) ordered,COALESCE(SUM(payable),0) payable,"+
                "COALESCE(SUM(paid),0) paid,COALESCE(SUM(payable-paid),0) unpaid FROM erp_purchases WHERE store_id=?",s);
    }
    public void event(long id,String type,long order,String payload) {
        check(id>0 && order>=0 && type!=null && type.matches("ORDER_[A-Z_]{1,48}") && payload!=null && payload.length()<=16384,"事件格式不正确");
        tx.executeWithoutResult(status->{
            db.update("INSERT INTO erp_event_inbox(event_id,event_type,order_id,payload) VALUES(?,?,?,?) ON DUPLICATE KEY UPDATE event_id=event_id",id,type,order,payload);
            var row=db.queryForMap("SELECT event_type,order_id,payload FROM erp_event_inbox WHERE event_id=?",id);
            check(type.equals(row.get("event_type")) && order==num(row,"order_id") && decode(row.get("payload").toString()).equals(decode(payload)),"事件编号内容冲突");
        });
    }
    private Map<String,Object> owned(String table,long store,Long id) {
        check(id!=null && id>0,"单据或物料编号无效");
        var rows=db.queryForList("SELECT * FROM "+table+" WHERE store_id=? AND id=? FOR UPDATE",store,id);
        if(rows.isEmpty())throw new BizException(404,"记录不存在或不属于本门店");return rows.getFirst();
    }
    private long lastId(){return Objects.requireNonNull(db.queryForObject("SELECT LAST_INSERT_ID()",Long.class));}
    private static long num(Map<String,Object> row,String k){return ((Number)row.get(k)).longValue();}
    private static BigDecimal decimal(Map<String,Object> row,String k){return new BigDecimal(row.get(k).toString());}
    private static void check(boolean value,String message){if(!value)throw new BizException(400,message);}
    private static String text(String s,int max){check(s!=null && !s.isBlank() && s.trim().length()<=max,"文本不能为空或超过长度限制");return s.trim();}
    private static BigDecimal positive(BigDecimal n,int scale){check(n!=null && n.signum()>0 && n.scale()<=scale,"数量、单价或金额必须为正数且精度正确");bounded(n);return n;}
    private static BigDecimal quantity(BigDecimal n){check(n!=null && n.signum()>=0,"数量不能为负数");try{n=n.setScale(3,RoundingMode.UNNECESSARY);}catch(ArithmeticException e){throw new BizException(400,"基础单位数量最多3位小数");}bounded(n);return n;}
    private static BigDecimal money(BigDecimal n){return n.setScale(2,RoundingMode.HALF_UP);}
    private static void bounded(BigDecimal n){check(n.abs().compareTo(new BigDecimal("999999999"))<=0,"数值超出允许范围");}
    private String encode(Object value){try{return json.writeValueAsString(value);}catch(Exception e){throw new IllegalStateException(e);}}
    private Map<String,Object> decode(String value){try{return json.readValue(value,new TypeReference<>(){});}catch(Exception e){throw new BizException(400,"JSON格式错误");}}
    private static String hash(String value){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
}
