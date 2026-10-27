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
    JdbcTemplate admin,db;String schema;ErpService first,second;ObjectMapper json=new ObjectMapper();long material,supplier,purchase;
    @BeforeEach void setup()throws Exception {
        String base="jdbc:mysql://"+System.getenv().getOrDefault("TAKEOUT_DB_HOST","127.0.0.1")+":"+System.getenv().getOrDefault("TAKEOUT_DB_PORT","3310")+"/";
        String opts="?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user=System.getenv().getOrDefault("TAKEOUT_DB_USERNAME","root"),password=System.getenv("TAKEOUT_DB_PASSWORD");
        admin=new JdbcTemplate(new DriverManagerDataSource(base+opts,user,password));schema="takeout_erp_test_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE `"+schema+"`");
        var source=new DriverManagerDataSource(base+schema+opts,user,password);
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
    @AfterEach void cleanup(){if(schema!=null)admin.execute("DROP DATABASE `"+schema+"`");}
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
    @Test void inboxDeduplicatesDurablyAndRejectsContentCollision(){
        first.event(1,"ORDER_PAID",100,"{\"amount\":10}");second.event(1,"ORDER_PAID",100,"{\"amount\":10}");
        assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM erp_event_inbox",Integer.class));
        assertThrows(BizException.class,()->second.event(1,"ORDER_PAID",100,"{\"amount\":11}"));
    }
}
