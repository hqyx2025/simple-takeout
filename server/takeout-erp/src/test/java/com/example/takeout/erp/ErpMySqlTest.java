package com.example.takeout.erp;

import com.example.takeout.common.BizException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import java.math.BigDecimal;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;

/** Uses only a generated schema on the explicitly opted-in test MySQL. */
@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST",matches="1")
class ErpMySqlTest {
    com.zaxxer.hikari.HikariDataSource pool;
    JdbcTemplate admin,db;String schema;ErpService first,second;ObjectMapper json=new ObjectMapper();long material,supplier,purchase;
    @BeforeEach void setup()throws Exception {
        String base="jdbc:mysql://"+System.getenv().getOrDefault("TAKEOUT_DB_HOST","127.0.0.1")+":"+System.getenv().getOrDefault("TAKEOUT_DB_PORT","3310")+"/";
        String opts="?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user=System.getenv().getOrDefault("TAKEOUT_DB_USERNAME","root"),password=System.getenv("TAKEOUT_DB_PASSWORD");
        admin=new JdbcTemplate(new DriverManagerDataSource(base+opts,user,password));schema="takeout_erp_test_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE `"+schema+"`");
        var source=new com.zaxxer.hikari.HikariDataSource();pool=source;
        source.setJdbcUrl(base+schema+opts);source.setUsername(user);source.setPassword(password);
        source.setMaximumPoolSize(2);source.setMinimumIdle(0);source.setConnectionTimeout(10000);
        new ResourceDatabasePopulator(new ClassPathResource("erp-schema.sql")).execute(source);
        // Apply twice without destroying existing data, including after the first transaction.
        db=new JdbcTemplate(source);
        first=new ErpService(db,new TransactionTemplate(new DataSourceTransactionManager(source)),json);
        second=new ErpService(new JdbcTemplate(source),new TransactionTemplate(new DataSourceTransactionManager(source)),json);
        supplier=run("suppliers","{\"name\":\"餐盒供应商\",\"contact\":\"门店采购\"}");
        material=run("materials","{\"name\":\"餐盒\",\"unit\":\"只\"}");
        new ResourceDatabasePopulator(new ClassPathResource("erp-schema.sql")).execute(source);
        purchase=run("purchases","{\"supplierId\":"+supplier+",\"lines\":[{\"materialId\":"+material+",\"quantity\":2,\"unitPrice\":30.005,\"purchaseUnit\":\"箱\",\"factor\":100}]}");
        run("submit","{\"id\":"+purchase+"}");run("confirm","{\"id\":"+purchase+"}");
    }
    @AfterEach void cleanup(){if(pool!=null)pool.close();if(schema!=null)admin.execute("DROP DATABASE `"+schema+"`");}
    ErpService.Command cmd(String value)throws Exception{return json.readValue(value,ErpService.Command.class);}
    long run(String action,String value)throws Exception{return ((Number)first.execute(10,99,action,UUID.randomUUID().toString(),cmd(value)).get("id")).longValue();}
    String receipt(String quantity){return "{\"id\":"+purchase+",\"lines\":[{\"materialId\":"+material+",\"quantity\":"+quantity+"}]}";}
    BigDecimal balance(){return db.queryForObject("SELECT balance FROM erp_materials WHERE id=?",BigDecimal.class,material);}
    @Test void completeFlowWithPartialReceiptsReviewReversalAndPayment()throws Exception {
        run("receive",receipt("1"));run("receive",receipt("1"));assertEquals(new BigDecimal("200.000"),balance());
        assertEquals(new BigDecimal("60.01"),first.finance(10).get("payable"));
        long adjustment=run("adjust","{\"materialId\":"+material+",\"kind\":\"LOSS\",\"quantity\":5,\"reason\":\"破损\"}");
        var review=cmd("{\"id\":"+adjustment+",\"approve\":true}");
        assertThrows(BizException.class,()->first.execute(10,99,"review",UUID.randomUUID().toString(),review));
        second.execute(10,2,"review",UUID.randomUUID().toString(),review);assertEquals(new BigDecimal("195.000"),balance());
        assertThrows(BizException.class,()->second.execute(10,2,"review",UUID.randomUUID().toString(),review));
        long ledger=db.queryForObject("SELECT id FROM erp_ledger WHERE source_type='ADJUST'",Long.class);
        run("reverse","{\"id\":"+ledger+",\"reason\":\"复核纠正\"}");assertEquals(new BigDecimal("200.000"),balance());
        run("pay","{\"id\":"+purchase+",\"amount\":60.01,\"reference\":\"BANK-001\"}");
        assertEquals(new BigDecimal("0.00"),first.finance(10).get("unpaid"));
        assertEquals(1,first.list(10,"payments",0,50,purchase,null).size());
        assertTrue(first.list(11,"ledger",0,50,null,null).isEmpty());
        assertThrows(BizException.class,()->first.lines(11,purchase));
        assertEquals(new BigDecimal("200.000"),db.queryForObject("SELECT SUM(delta) FROM erp_ledger",BigDecimal.class));
    }
    @Test void identicalRetryAcrossIndependentInstancesCommitsOneReceipt()throws Exception {
        String key=UUID.randomUUID().toString();var c=cmd(receipt("1"));
        var tasks=new ArrayList<Callable<Map<String,Object>>>();for(int i=0;i<24;i++){final var service=i%2==0?first:second;tasks.add(()->service.execute(10,99,"receive",key,c));}
        try(var pool=Executors.newFixedThreadPool(12)){var results=pool.invokeAll(tasks);long id=((Number)results.getFirst().get().get("id")).longValue();for(var result:results)assertEquals(id,((Number)result.get().get("id")).longValue());}
        assertEquals(new BigDecimal("100.000"),balance());assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM erp_receipts",Integer.class));
        assertThrows(BizException.class,()->first.execute(10,99,"receive",key,cmd(receipt("2"))));
    }
    @Test void competingReceiptsCannotOverReceiveAndPaymentsCannotOverpay()throws Exception {
        var c=cmd(receipt("1"));var accepted=new AtomicInteger();
        try(var pool=Executors.newFixedThreadPool(12)) {
            List<Callable<Void>> tasks=new ArrayList<>();for(int i=0;i<24;i++){var service=i%2==0?first:second;tasks.add(()->{try{service.execute(10,99,"receive",UUID.randomUUID().toString(),c);accepted.incrementAndGet();}catch(BizException expected){}return null;});}
            for(var result:pool.invokeAll(tasks))result.get();
            assertEquals(2,accepted.get());accepted.set(0);tasks.clear();
            var pay=cmd("{\"id\":"+purchase+",\"amount\":60.01,\"reference\":\"BANK-SAME\"}");
            for(int i=0;i<24;i++){var service=i%2==0?first:second;tasks.add(()->{try{service.execute(10,99,"pay",UUID.randomUUID().toString(),pay);accepted.incrementAndGet();}catch(BizException expected){}return null;});}
            for(var result:pool.invokeAll(tasks))result.get();
        }
        assertEquals(1,accepted.get());assertEquals(new BigDecimal("200.000"),balance());assertEquals(new BigDecimal("60.01"),first.finance(10).get("paid"));
    }
    @Test void receiptReversalPreservesHistoryAndPayableAndRejectsRepeatedReversal()throws Exception {
        long receipt=run("receive",receipt("1"));long id=run("reverse-receipt","{\"id\":"+receipt+",\"reason\":\"到货登记错误\"}");
        assertEquals(receipt,id);assertEquals(new BigDecimal("0.000"),balance());assertEquals(new BigDecimal("0.00"),first.finance(10).get("payable"));
        assertEquals(2,db.queryForObject("SELECT COUNT(*) FROM erp_ledger",Integer.class));
        assertThrows(BizException.class,()->run("reverse-receipt","{\"id\":"+receipt+",\"reason\":\"重复\"}"));
        run("receive",receipt("2"));assertEquals(new BigDecimal("200.000"),balance());
    }
    @Test void staleCountAndClosedPurchaseCannotMutateStock()throws Exception {
        run("receive",receipt("1"));long count=run("adjust","{\"materialId\":"+material+",\"kind\":\"COUNT\",\"quantity\":99,\"reason\":\"盘点\"}");
        run("receive",receipt("1"));
        assertThrows(BizException.class,()->second.execute(10,2,"review",UUID.randomUUID().toString(),cmd("{\"id\":"+count+",\"approve\":true}")));
        run("close","{\"id\":"+purchase+"}");assertThrows(BizException.class,()->run("receive",receipt("0.1")));assertEquals(new BigDecimal("200.000"),balance());
    }
    @Test void paymentCorrectionsRefundsAndReceiptReversalKeepAppendOnlyHistory()throws Exception {
        long receipt=run("receive",receipt("2"));
        long payment=run("pay","{\"id\":"+purchase+",\"amount\":60.01,\"reference\":\"BANK-ORIGINAL\"}");
        run("payment-correct","{\"id\":"+payment+",\"reference\":\"BANK-CORRECTED\",\"reason\":\"凭证录入错误\"}");
        assertThrows(BizException.class,()->run("reverse-receipt","{\"id\":"+receipt+",\"reason\":\"未退款\"}"));
        var refund=cmd("{\"id\":"+payment+",\"amount\":30,\"reference\":\"REFUND-1\",\"reason\":\"供应商退回货款\"}");
        String key=UUID.randomUUID().toString();
        assertEquals(first.execute(10,99,"supplier-refund",key,refund),second.execute(10,99,"supplier-refund",key,refund));
        assertEquals(new BigDecimal("30.01"),first.finance(10).get("paid"));
        assertThrows(BizException.class,()->run("supplier-refund","{\"id\":"+payment+",\"amount\":30.02,\"reference\":\"REFUND-TOO-MUCH\",\"reason\":\"超额\"}"));
        run("reverse-payment","{\"id\":"+payment+",\"reason\":\"剩余付款登记错误\"}");
        assertThrows(BizException.class,()->run("reverse-payment","{\"id\":"+payment+",\"reason\":\"重复\"}"));
        run("reverse-receipt","{\"id\":"+receipt+",\"reason\":\"退货闭环\"}");
        assertEquals(new BigDecimal("0.00"),first.finance(10).get("paid"));
        assertEquals(new BigDecimal("0.00"),first.finance(10).get("payable"));
        assertEquals("BANK-ORIGINAL",first.list(10,"payments",0,50,purchase,null).getFirst().get("reference"));
        assertEquals(3,first.list(10,"payment-events",0,50,purchase,null).size());
        assertThrows(BizException.class,()->first.execute(11,99,"supplier-refund",UUID.randomUUID().toString(),refund));
        for(String amount:List.of("0","-1","0.001","9999999999"))
            assertThrows(BizException.class,()->run("supplier-refund","{\"id\":"+payment+",\"amount\":"+amount+",\"reference\":\"INVALID\",\"reason\":\"金额校验\"}"));
        assertTrue(first.list(11,"payment-events",0,50,purchase,null).isEmpty());
    }
    @Test void competingRefundAndReversalCannotReduceOnePaymentTwice()throws Exception {
        run("receive",receipt("2"));long payment=run("pay","{\"id\":"+purchase+",\"amount\":60.01,\"reference\":\"BANK-RACE\"}");
        var accepted=new AtomicInteger();
        try(var pool=Executors.newFixedThreadPool(8)) {
            var tasks=new ArrayList<Callable<Void>>();
            for(int i=0;i<16;i++) {
                final int n=i;var service=i%2==0?first:second;
                tasks.add(()->{try {
                    service.execute(10,99,n%2==0?"supplier-refund":"reverse-payment",UUID.randomUUID().toString(),
                            cmd("{\"id\":"+payment+",\"amount\":60.01,\"reference\":\"REFUND-"+n+"\",\"reason\":\"并发核对\"}"));
                    accepted.incrementAndGet();
                }catch(BizException expected){}return null;});
            }
            for(var result:pool.invokeAll(tasks))result.get();
        }
        assertEquals(1,accepted.get());assertEquals(new BigDecimal("0.00"),first.finance(10).get("paid"));
        assertEquals(1,first.list(10,"payment-events",0,50,purchase,null).size());
    }
    @Test void oldPaymentSchemaMigrationReservesReferencesAndPreservesHistory()throws Exception {
        run("receive",receipt("2"));long payment=run("pay","{\"id\":"+purchase+",\"amount\":10,\"reference\":\"OLD-BANK\"}");
        // Simulate the previous ERP schema, with an existing immutable payment.
        db.execute("DROP TABLE erp_payment_events");db.execute("DROP TABLE erp_payment_references");
        var migration=new ResourceDatabasePopulator(new ClassPathResource("erp-schema.sql"));
        migration.execute(Objects.requireNonNull(db.getDataSource()));migration.execute(db.getDataSource());
        assertEquals("OLD-BANK",first.list(10,"payments",0,50,purchase,null).getFirst().get("reference"));
        assertEquals(new BigDecimal("10.00"),first.finance(10).get("paid"));
        assertThrows(org.springframework.dao.DuplicateKeyException.class,()->run("payment-correct","{\"id\":"+payment+",\"reference\":\"OLD-BANK\",\"reason\":\"不得复用历史凭证\"}"));
        run("payment-correct","{\"id\":"+payment+",\"reference\":\"NEW-BANK\",\"reason\":\"旧付款凭证纠正\"}");
        assertEquals(1,first.list(10,"payment-events",0,50,purchase,null).size());
    }
    @Test void catalogSearchTraversesBeyondOneHundredAndEscapesWildcards()throws Exception {
        for(int i=0;i<105;i++)run("materials","{\"name\":\"分页物料"+i+"\",\"unit\":\"只\"}");
        run("materials","{\"name\":\"百分%物料\",\"unit\":\"只\"}");
        var firstPage=first.list(10,"materials",0,50,null,null,"分页物料",null);
        var secondPage=first.list(10,"materials",((Number)firstPage.getLast().get("id")).longValue(),50,null,null,"分页物料",null);
        var thirdPage=first.list(10,"materials",((Number)secondPage.getLast().get("id")).longValue(),50,null,null,"分页物料",null);
        assertEquals(50,firstPage.size());assertEquals(50,secondPage.size());assertEquals(5,thirdPage.size());
        assertEquals(1,first.list(10,"materials",0,50,null,null,"%",null).size());
        assertTrue(first.list(11,"materials",0,50,null,null,"分页物料",null).isEmpty());
        for(int i=0;i<105;i++)run("suppliers","{\"name\":\"分页供应商"+i+"\",\"contact\":\"联系"+i+"\"}");
        long disabled=run("suppliers","{\"name\":\"分页供应商停用\",\"contact\":\"联系停用\"}");
        run("supplier-status","{\"id\":"+disabled+",\"enabled\":false}");
        var page=first.list(10,"suppliers",0,1000,null,null,"分页供应商",true);
        assertEquals(100,page.size());assertTrue(page.stream().noneMatch(row->((Number)row.get("id")).longValue()==disabled));
        assertEquals(5,first.list(10,"suppliers",((Number)page.getLast().get("id")).longValue(),50,null,null,"分页供应商",true).size());
        assertEquals(1,first.list(10,"suppliers",0,50,null,null,"联系104",true).size());
    }
    @Test void inboxDeduplicatesDurablyAndRejectsContentCollision(){
        first.event(1,"ORDER_PAID",100,"{\"amount\":10}");second.event(1,"ORDER_PAID",100,"{\"amount\":10}");
        assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM erp_event_inbox",Integer.class));
        assertThrows(BizException.class,()->second.event(1,"ORDER_PAID",100,"{\"amount\":11}"));
    }
}
