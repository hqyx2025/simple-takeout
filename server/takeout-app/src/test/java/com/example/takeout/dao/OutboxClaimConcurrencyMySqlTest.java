package com.example.takeout.dao;

import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.UUID;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST", matches="1")
class OutboxClaimConcurrencyMySqlTest {
    @Test @SuppressWarnings("unchecked")
    void pausedClaimDoesNotBlockNewBusinessEventInserts() throws Exception {
        String base="jdbc:mysql://"+System.getenv().getOrDefault("TAKEOUT_DB_HOST","127.0.0.1")+":"
                +System.getenv().getOrDefault("TAKEOUT_DB_PORT","3310")+"/";
        String options="?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user=System.getenv().getOrDefault("TAKEOUT_DB_USERNAME","root");
        String password=System.getenv("TAKEOUT_DB_PASSWORD");
        var admin=new JdbcTemplate(new DriverManagerDataSource(base+options,user,password));
        String database="takeout_outbox_claim_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE `"+database+"`");
        var selected=new CountDownLatch(1);var release=new CountDownLatch(1);
        try(var pool=new HikariDataSource();var workers=Executors.newFixedThreadPool(2)) {
            pool.setJdbcUrl(base+database+options);pool.setUsername(user);pool.setPassword(password);
            pool.setMaximumPoolSize(4);pool.setMinimumIdle(0);pool.setConnectionTimeout(10000);
            new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(pool);
            var jdbc=new JdbcTemplate(pool);var scanning=spy(jdbc);
            var businessTx=new TransactionTemplate(new DataSourceTransactionManager(pool));
            var relay=new OutboxEventDao(scanning,businessTx);var writes=new OutboxEventDao(jdbc,businessTx);
            long original=writes.insert("ORDER_CREATED",1,"{}","2026-11-12 00:00:00");
            doAnswer(call -> {
                Object rows=call.callRealMethod();selected.countDown();
                assertTrue(release.await(10,TimeUnit.SECONDS));return rows;
            }).when(scanning).query(contains("FOR UPDATE SKIP LOCKED"),any(RowMapper.class),anyLong(),anyInt());
            Future<?> claimed=workers.submit(() -> relay.claimPending(5,"worker",1000,100000));
            try {
                assertTrue(selected.await(5,TimeUnit.SECONDS),"claim must hold a real open transaction");
                Future<Long> inserted=workers.submit(() -> writes.insert("ORDER_PAID",2,"{}","2026-11-12 00:00:01"));
                long next=assertDoesNotThrow(() -> inserted.get(2,TimeUnit.SECONDS),
                        "An unfinished relay claim must not block a new business outbox insert");
                assertTrue(next>original);
                assertEquals("",jdbc.queryForObject("SELECT owner FROM outbox_events WHERE id=?",String.class,next));
            } finally { release.countDown(); }
            claimed.get(5,TimeUnit.SECONDS);
            assertEquals("worker",jdbc.queryForObject("SELECT owner FROM outbox_events WHERE id=?",String.class,original));
            assertEquals(TransactionDefinition.ISOLATION_DEFAULT,businessTx.getIsolationLevel(),
                    "claim isolation must not change the shared business transaction template");
            assertEquals("REPEATABLE-READ",jdbc.queryForObject("SELECT @@transaction_isolation",String.class));
            System.out.println("[Outbox claim] real-MySQL concurrent insert committed before held claim released; business isolation unchanged");
        } finally { release.countDown();admin.execute("DROP DATABASE `"+database+"`"); }
    }
}
