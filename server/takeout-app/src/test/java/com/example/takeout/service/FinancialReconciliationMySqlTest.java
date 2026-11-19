package com.example.takeout.service;

import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.UUID;
import java.math.BigDecimal;
import static org.junit.jupiter.api.Assertions.*;

@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST",matches="1")
class FinancialReconciliationMySqlTest {
    private JdbcTemplate admin,db;
    private String database;
    private TransactionTemplate tx;
    @BeforeEach void start() {
        String base="jdbc:mysql://"+System.getenv().getOrDefault("TAKEOUT_DB_HOST","127.0.0.1")+":"
                +System.getenv().getOrDefault("TAKEOUT_DB_PORT","3310")+"/";
        String options="?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user=System.getenv().getOrDefault("TAKEOUT_DB_USERNAME","root"),password=System.getenv("TAKEOUT_DB_PASSWORD");
        admin=new JdbcTemplate(new DriverManagerDataSource(base+options,user,password));
        database="boundary_reconcile_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE "+database);
        var source=new DriverManagerDataSource(base+database+options,user,password);
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        db=new JdbcTemplate(source);tx=new TransactionTemplate(new DataSourceTransactionManager(source));
        db.update("INSERT INTO users(id,username,phone,password,balance,create_time) VALUES(1,'buyer','13800000001','hash',100,NOW())");
        db.update("INSERT INTO orders(id,order_no,user_id,store_id,store_name,status,items,address,pay_amount,create_time,pay_time) "
                +"VALUES(1,'reconcile-1',1,1,'store',1,'[]','{}',10,NOW(),NOW())");
        db.update("INSERT INTO payment_records(order_id,user_id,amount,type,channel,status,create_time) VALUES(1,1,10,'PAY','BALANCE','SUCCESS',NOW())");
    }
    @AfterEach void stop() { if(database!=null)admin.execute("DROP DATABASE "+database); }

    @Test void detectsDuplicateChargeAndKeepsEvidenceWithoutChangingMoney() {
        var service=new FinancialReconciliationService(db,tx);
        service.scanBatch();assertTrue(service.issues(20).isEmpty());
        db.update("INSERT INTO payment_records(order_id,user_id,amount,type,channel,status,create_time) VALUES(1,1,10,'PAY','BALANCE','SUCCESS',NOW())");
        db.update("UPDATE financial_reconciliation_progress SET complete=0,last_id=0");
        service.scanBatch();
        assertFalse(service.issues(20).isEmpty(), "Duplicate debit must create a reconciliation issue");
        assertEquals("ORDER_MONEY",service.issues(20).getFirst().get("check_type"));
        assertEquals(new BigDecimal("100.00"),db.queryForObject("SELECT balance FROM users WHERE id=1",BigDecimal.class));
        assertEquals(2,db.queryForObject("SELECT COUNT(*) FROM payment_records",Integer.class));
        db.update("DELETE FROM payment_records ORDER BY id DESC LIMIT 1");
        db.update("UPDATE financial_reconciliation_progress SET complete=0,last_id=0");
        service.scanBatch();assertNotNull(service.issues(20).getFirst().get("resolved_at"));
    }

    @Test void walletMovementsCommitAndRollbackWithTheActualBalance() {
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM wallet_movements",Integer.class));
        tx.executeWithoutResult(status->db.update("UPDATE users SET balance=balance-10 WHERE id=1"));
        tx.executeWithoutResult(status->{db.update("UPDATE users SET balance=balance+5 WHERE id=1");status.setRollbackOnly();});
        assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM wallet_movements",Integer.class));
        assertEquals(new BigDecimal("-10.00"),db.queryForObject("SELECT delta FROM wallet_movements",BigDecimal.class));
        assertEquals(new BigDecimal("90.00"),db.queryForObject("SELECT balance FROM users WHERE id=1",BigDecimal.class));
        new FinancialReconciliationService(db,tx).scanBatch();
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM financial_reconciliation_issues",Integer.class));
    }

    @Test void refundedLateProviderPaymentIsNotReportedAsADuplicateBusinessCharge() {
        db.update("INSERT INTO payment_transactions(order_id,user_id,channel,amount,out_trade_no,status,create_time) "
                + "VALUES(1,1,'ALIPAY',10,'late-1','LATE_REFUNDED',NOW())");
        db.update("INSERT INTO payment_records(order_id,user_id,amount,type,channel,status,create_time) "
                + "VALUES(1,1,10,'PAY','ALIPAY','SUCCESS',NOW()),(1,1,10,'REFUND','ALIPAY','SUCCESS',NOW())");
        var service=new FinancialReconciliationService(db,tx);service.scanBatch();
        assertTrue(service.issues(20).isEmpty());
    }

    @Test void duplicatePartialRefundIsDetectedEvenBelowOriginalPaymentAmount() {
        db.update("INSERT INTO refund_records(order_id,user_id,merchant_id,amount,reason,status,apply_time) "
                + "VALUES(1,1,2,2,'partial','REFUNDED',NOW())");
        db.update("INSERT INTO payment_records(order_id,user_id,amount,type,channel,status,create_time) "
                + "VALUES(1,1,2,'REFUND','BALANCE','SUCCESS',NOW())");
        var service=new FinancialReconciliationService(db,tx);service.scanBatch();
        assertTrue(service.issues(20).isEmpty());
        db.update("INSERT INTO payment_records(order_id,user_id,amount,type,channel,status,create_time) "
                + "VALUES(1,1,2,'REFUND','BALANCE','SUCCESS',NOW())");
        db.update("UPDATE financial_reconciliation_progress SET complete=0,last_id=0");service.scanBatch();
        assertFalse(service.issues(20).isEmpty());
    }
}
