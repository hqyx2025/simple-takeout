package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.*;
import com.example.takeout.model.MarketingActivity;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST",matches="1")
class BusinessRulesMySqlTest {
    private com.zaxxer.hikari.HikariDataSource pool;
    private JdbcTemplate admin,db; private String schema; private TransactionTemplate tx;
    @BeforeEach void setup() {
        String base="jdbc:mysql://"+System.getenv().getOrDefault("TAKEOUT_DB_HOST","127.0.0.1")+":"+System.getenv().getOrDefault("TAKEOUT_DB_PORT","3310")+"/";
        String options="?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user=System.getenv().getOrDefault("TAKEOUT_DB_USERNAME","root"),password=System.getenv().getOrDefault("TAKEOUT_DB_PASSWORD","");
        admin=new JdbcTemplate(new DriverManagerDataSource(base+options,user,password));
        schema="takeout_rules_test_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE `"+schema+"`");
        var source=new com.zaxxer.hikari.HikariDataSource();pool=source;
        source.setJdbcUrl(base+schema+options);source.setUsername(user);source.setPassword(password);
        source.setMaximumPoolSize(2);source.setMinimumIdle(0);source.setConnectionTimeout(10000);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql"),new ClassPathResource("business-rules.sql")).execute(source);
        db=new JdbcTemplate(source);tx=new TransactionTemplate(new DataSourceTransactionManager(source));
    }
    @AfterEach void cleanup() { if(pool!=null)pool.close(); if(schema!=null)admin.execute("DROP DATABASE `"+schema+"`"); }

    @Test void twoInstancesCannotReserveTheSameNewCustomerBenefitAndUnpaidCancellationReleasesIt() throws Exception {
        var first=new PromotionService(db,new ObjectMapper());
        var second=new PromotionService(new JdbcTemplate(db.getDataSource()),new ObjectMapper());
        var activity=new MarketingActivity(1,10,"NEW_USER","首单",0,3,0,0,"","",1,"");
        var pool=Executors.newFixedThreadPool(2);
        try {
            var start=new CountDownLatch(1);var futures=new ArrayList<Future<Boolean>>();
            for(int index=0;index<2;index++) {final int i=index;futures.add(pool.submit(()->{
                start.await();return tx.execute(status->{
                    var service=i==0?first:second;
                    var quote=service.quote(1,10,new BigDecimal("20.00"),List.of(activity));
                    service.bind(1,10,i+1,new BigDecimal("20.00"),BigDecimal.ZERO,quote);
                    return quote.newCustomerDiscount().signum()>0;
                });
            }));}
            start.countDown();int awarded=0;for(var future:futures)if(future.get(15,TimeUnit.SECONDS))awarded++;
            assertEquals(1,awarded);
            long reserved=db.queryForObject("SELECT order_id FROM promotion_claims WHERE user_id=1 AND store_id=10",Long.class);
            tx.executeWithoutResult(status->first.releaseUnpaid(reserved));
            tx.executeWithoutResult(status->{
                var quote=first.quote(1,10,new BigDecimal("20.00"),List.of(activity));
                assertEquals(new BigDecimal("3.00"),quote.newCustomerDiscount());
                first.bind(1,10,3,new BigDecimal("20.00"),BigDecimal.ZERO,quote);first.paid(3);
            });
            tx.executeWithoutResult(status->assertEquals(BigDecimal.ZERO,second.quote(1,10,new BigDecimal("20.00"),List.of(activity)).newCustomerDiscount()));
            new ResourceDatabasePopulator(new ClassPathResource("business-rules.sql")).execute(db.getDataSource());
            assertEquals("USED",db.queryForObject("SELECT state FROM promotion_claims WHERE user_id=1 AND store_id=10",String.class));
        } finally {pool.shutdownNow();}
    }

    @Test void modeSnapshotsSurviveStoreChangesAndIssuesAreIdempotentAndReassignOnlyBeforePickup() {
        db.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address,create_time,rider_id,ready_time) VALUES(1,'RULE1',1,10,'门店',2,'[]','{}','2026-01-01 00:00:00',7,'2026-01-01 00:10:00')");
        var stores=mock(StoreDao.class);
        var orders=new OrderDao(db);
        var service=new OrderOperationsService(db,orders,stores,new RiderDao(db),mock(ObjectProvider.class),mock(ObjectProvider.class));
        tx.executeWithoutResult(status->service.snapshot(1,10));
        db.update("INSERT INTO store_fulfillment(store_id,mode) VALUES(10,'MERCHANT')");
        assertEquals("RIDER",service.mode(1));
        var issue=tx.execute(status->service.report(1,0,1,"CUSTOMER_UNREACHABLE","请平台核实","request-for-issue-1"));
        var replay=tx.execute(status->service.report(1,0,1,"CUSTOMER_UNREACHABLE","请平台核实","request-for-issue-1"));
        assertEquals(issue.id(),replay.id());
        assertThrows(BizException.class,()->tx.execute(status->service.report(2,0,1,"OTHER","越权","request-for-issue-2")));
        tx.executeWithoutResult(status->service.resolve(99,issue.id(),"REASSIGN","核实后改派"));
        assertEquals(0,orders.findRiderId(1));
        assertEquals("RESOLVED",service.issues(1,0,1).getFirst().status());
        db.update("UPDATE orders SET status=3,rider_id=8 WHERE id=1");
        var second=tx.execute(status->service.report(1,0,1,"ADDRESS_PROBLEM","门牌需核实","request-for-issue-3"));
        assertThrows(BizException.class,()->tx.execute(status->service.resolve(99,second.id(),"REASSIGN","不能无交接改派")));
        assertEquals(8,orders.findRiderId(1));
    }
    @Test void operatingFinanceMatchesPartialRefundsSettlementsRiderIncomeAndDebt() {
        db.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,escrow_status,items,address,pay_amount,delivery_fee,create_time,pay_time,rider_id) VALUES" +
                "(1,'F1',1,10,'门店',4,0,'[]','{}',100,10,'2026-01-01','2026-01-01',0)," +
                "(2,'F2',1,10,'门店',4,1,'[]','{}',100,10,'2026-01-01','2026-01-01',7)," +
                "(3,'F3',1,10,'门店',6,2,'[]','{}',50,5,'2026-01-01','2026-01-01',7)");
        db.update("INSERT INTO payment_records(order_id,user_id,amount,type,channel,status,create_time) VALUES" +
                "(1,1,100,'PAY','BALANCE','SUCCESS','2026-01-01'),(2,1,100,'PAY','BALANCE','SUCCESS','2026-01-01')," +
                "(3,1,50,'PAY','BALANCE','SUCCESS','2026-01-01'),(1,1,20,'REFUND','BALANCE','SUCCESS','2026-01-01')," +
                "(2,1,30,'REFUND','BALANCE','SUCCESS','2026-01-01'),(3,1,50,'REFUND','BALANCE','SUCCESS','2026-01-01')");
        db.update("INSERT INTO refund_records(id,order_id,user_id,merchant_id,amount,status,apply_time,merchant_amount,platform_amount,settled_before) VALUES" +
                "(1,1,1,99,20,'REFUNDED','2026-01-01',20,0,0),(2,2,1,99,30,'REFUNDED','2026-01-01',30,0,1)," +
                "(3,3,1,99,50,'REFUNDED','2026-01-01',45,5,1)");
        db.update("INSERT INTO order_settlements(order_id,merchant_id,net_amount,debt_repaid,wallet_credited,settled_at) VALUES" +
                "(2,99,90,0,90,NOW()),(3,99,45,0,45,NOW())");
        db.update("INSERT INTO after_sales_ledger(refund_id,order_id,merchant_id,merchant_amount,wallet_deducted,debt_amount,platform_amount,create_time) VALUES" +
                "(2,2,99,30,10,20,0,NOW()),(3,3,99,45,0,45,5,NOW())");
        var stores=mock(StoreDao.class);
        when(stores.findById(10)).thenReturn(Optional.of(mock(com.example.takeout.model.Store.class)));
        String secret="isolated-test-integration-secret-123456789";
        var controller=new com.example.takeout.controller.ErpAuthorityController(stores,db,secret);
        Object data=controller.finance(99,2,10,secret).data();
        var facts=(Map<?,?>)data;
        assertEquals(250.0,((Number)facts.get("receipts")).doubleValue());
        assertEquals(100.0,((Number)facts.get("refunds")).doubleValue());
        assertEquals(80.0,((Number)facts.get("held")).doubleValue());
        assertEquals(60.0,((Number)facts.get("merchantSettled")).doubleValue());
        assertEquals(15.0,((Number)facts.get("deliveryAllocated")).doubleValue());
        assertEquals(5.0,((Number)facts.get("platformAfterSalesCost")).doubleValue());
        assertEquals(65.0,((Number)facts.get("merchantDebt")).doubleValue());
        assertEquals(135.0,((Number)facts.get("walletCredited")).doubleValue());
    }

}
