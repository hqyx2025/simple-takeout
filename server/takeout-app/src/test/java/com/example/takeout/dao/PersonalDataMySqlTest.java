package com.example.takeout.dao;

import com.example.takeout.config.PersonalDataMigration;
import com.example.takeout.model.Order;
import com.example.takeout.service.PersonalDataCrypto;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;

@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST",matches="1")
class PersonalDataMySqlTest {
    private static final String NOW="2026-11-07 12:00:00";
    JdbcTemplate admin,db; String schema,secret,index; TransactionTemplate tx; PersonalDataCrypto crypto; UserDao users;
    @BeforeEach void start() {
        String base="jdbc:mysql://"+System.getenv().getOrDefault("TAKEOUT_DB_HOST","127.0.0.1")+":"+System.getenv().getOrDefault("TAKEOUT_DB_PORT","3310")+"/";
        String options="?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user=System.getenv().getOrDefault("TAKEOUT_DB_USERNAME","root"), password=System.getenv("TAKEOUT_DB_PASSWORD");
        admin=new JdbcTemplate(new DriverManagerDataSource(base+options,user,password));
        schema="takeout_personal_"+UUID.randomUUID().toString().replace("-",""); admin.execute("CREATE DATABASE `"+schema+"`");
        var source=new DriverManagerDataSource(base+schema+options,user,password); db=new JdbcTemplate(source);
        tx=new TransactionTemplate(new DataSourceTransactionManager(source));
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
        Flyway.configure().dataSource(source).locations("classpath:db/migration/app").baselineOnMigrate(true).baselineVersion("0").load().migrate();
        secret=key();index=key();crypto=new PersonalDataCrypto(secret,index,"",new ObjectMapper());users=new UserDao(db,crypto);
    }
    @AfterEach void stop(){if(schema!=null)admin.execute("DROP DATABASE `"+schema+"`");}
    private String key(){byte[] bytes=new byte[32];new java.security.SecureRandom().nextBytes(bytes);return Base64.getEncoder().encodeToString(bytes);}
    private PersonalDataMigration migration(PersonalDataCrypto value){return new PersonalDataMigration(db,tx,value,new UserDao(db,value),new AddressDao(db,value),new RiderDao(db,value));}

    @Test void encryptedPhoneSearchMatchesMysqlLikeIncludingWildcardsCountsAndPagination() {
        var first=tx.execute(status->users.insert("alpha","13800138999","unused",0,25,NOW));
        var second=tx.execute(status->users.insert("beta","13900139001","unused",1,35,NOW));
        var third=tx.execute(status->users.insert("gamma","13112345678","unused",0,45,NOW));
        var raw=db.queryForMap("SELECT phone,phone_encrypted,phone_lookup FROM users WHERE id=?",first.id());
        assertFalse(raw.get("phone").toString().contains(first.phone()));
        assertFalse(raw.get("phone_encrypted").toString().contains(first.phone()));
        assertTrue(raw.get("phone_encrypted").toString().startsWith("pd1:"));
        assertEquals(first.phone(),users.findByPhone(first.phone()).orElseThrow().phone());
        Long lockedId=tx.execute(status->users.findByPhoneForUpdate(first.phone()).orElseThrow().id());
        assertEquals(first.id(),lockedId.longValue());
        var all=List.of(first,second,third);
        for(String query:List.of("138","001","1_8","13%00","%00_1%","\\%","\\","___________","____________","x","%","%%","alpha","")) {
            var expected=all.stream().filter(user->Boolean.TRUE.equals(db.queryForObject("SELECT (? LIKE ?) OR (? LIKE ?)",Boolean.class,
                    user.username(),"%"+query+"%",user.phone(),"%"+query+"%"))).map(user->user.id()).sorted(Comparator.reverseOrder()).toList();
            assertEquals(expected,users.listForAdmin(null,null,query).stream().map(user->user.id()).toList(),"query="+query);
            assertEquals(expected.size(),users.countForAdmin(null,null,query),"count query="+query);
            if(!expected.isEmpty())assertEquals(expected.getFirst(),users.listForAdmin(null,null,query,1,0).getFirst().id());
        }
        tx.executeWithoutResult(status->users.updateProfile(first.id(),"alpha","13800999999"));
        assertTrue(users.findByPhone(first.phone()).isEmpty());assertEquals(first.id(),users.findByPhone("13800999999").orElseThrow().id());
        assertEquals(0,users.countForAdmin(null,null,"13899"));
        assertEquals(1,users.countForAdmin(null,null,"99999"));
        assertEquals(second.phone(),users.listEmployees().getFirst().phone());
        db.update("INSERT INTO employees(store_id,user_id,role_name,status,create_time) VALUES(10,?,'staff',1,?)",second.id(),NOW);
        assertEquals(second.phone(),new EmployeeDao(db,crypto).listByStore(10).getFirst().phone());
    }

    @Test void historicalPhoneAddressesCoordinatesAndSnapshotsSurviveRepeatMigrationAndKeyRotation() {
        var oldUser=new UserDao(db).insert("legacy","13800138999","unused",3,123.45,NOW);
        long addressId=new AddressDao(db).insert(oldUser.id(),"收件人",oldUser.phone(),"私人小区3栋502",1,22.8123456,108.3123456,"小区","3栋502","家",NOW);
        long riderId=tx.execute(status->new RiderDao(db).insert(oldUser.id(),"骑手",oldUser.phone(),NOW));
        new RiderDao(db).updateLocation(riderId,22.8123456,108.3123456,"私人接单位置");
        String snapshot="{\"name\":\"收件人\",\"phone\":\"13800138999\",\"detail\":\"私人小区3栋502\"}";
        long orderId=tx.execute(status->new OrderDao(db).insert(new Order(0,"private-history",oldUser.id(),10,"store",0,"[]",snapshot,10,0,0,10,"",0,0,NOW,"","","","","",0,"DELIVERY")));
        migration(crypto).run(new DefaultApplicationArguments());
        var address=new AddressDao(db,crypto).findByIdAndUser(addressId,oldUser.id()).orElseThrow();
        assertEquals("私人小区3栋502",address.detail());assertEquals(22.8123456,address.latitude(),0.00000001);
        assertEquals("",db.queryForObject("SELECT detail FROM addresses WHERE id=?",String.class,addressId));
        assertNull(db.queryForObject("SELECT latitude FROM addresses WHERE id=?",Double.class,addressId));
        assertEquals("",db.queryForObject("SELECT phone FROM riders WHERE id=?",String.class,riderId));
        assertEquals("私人接单位置",new RiderDao(db,crypto).findById(riderId).orElseThrow().locationAddress());
        assertEquals(snapshot,new OrderDao(db,crypto).findById(orderId).orElseThrow().address());
        String encrypted=db.queryForObject("SELECT address FROM orders WHERE id=?",String.class,orderId);
        assertFalse(encrypted.contains(oldUser.phone()));assertFalse(encrypted.contains("私人小区"));
        migration(crypto).run(new DefaultApplicationArguments());
        assertEquals(encrypted,db.queryForObject("SELECT address FROM orders WHERE id=?",String.class,orderId));
        String next=key();var rotated=new PersonalDataCrypto(next,index,secret,new ObjectMapper());
        migration(rotated).run(new DefaultApplicationArguments());
        var newOnly=new PersonalDataCrypto(next,index,"",new ObjectMapper());
        assertEquals(oldUser.phone(),new UserDao(db,newOnly).findById(oldUser.id()).orElseThrow().phone());
        assertEquals(snapshot,new OrderDao(db,newOnly).findById(orderId).orElseThrow().address());
        assertEquals(address,new AddressDao(db,newOnly).findByIdAndUser(addressId,oldUser.id()).orElseThrow());
        assertEquals(123.45,db.queryForObject("SELECT balance FROM users WHERE id=?",Double.class,oldUser.id()),0.001);
        assertThrows(IllegalStateException.class,()->migration(new PersonalDataCrypto(next,key(),secret,new ObjectMapper())).run(new DefaultApplicationArguments()));
    }

    @Test void overlappingRegistrationsKeepOneAccountAndOnePhoneIndexWithoutPartialWrites() throws Exception {
        AtomicInteger succeeded=new AtomicInteger(),rejected=new AtomicInteger();var start=new CountDownLatch(1);
        try(var pool=Executors.newFixedThreadPool(8)) {
            List<Future<?>> tasks=new ArrayList<>();
            for(int i=0;i<8;i++){int n=i;tasks.add(pool.submit(()->{
                try {assertTrue(start.await(5,TimeUnit.SECONDS));tx.executeWithoutResult(status->users.insert("parallel-"+n,"13800138999","unused",0,20,NOW));succeeded.incrementAndGet();}
                catch(org.springframework.dao.DuplicateKeyException expected){rejected.incrementAndGet();}
                catch(InterruptedException failure){throw new RuntimeException(failure);}
            }));}
            start.countDown();for(var task:tasks)task.get(15,TimeUnit.SECONDS);
        } finally {start.countDown();}
        assertEquals(1,succeeded.get());assertEquals(7,rejected.get());
        assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM users",Integer.class));
        assertEquals(66,db.queryForObject("SELECT COUNT(*) FROM user_phone_search",Integer.class));
        assertEquals(20,db.queryForObject("SELECT SUM(balance) FROM users",Integer.class));
    }

    @Test void differentPhonesCanRegisterConcurrentlyWithoutEmptyIndexRangeDeadlocks() throws Exception {
        var start=new CountDownLatch(1); var succeeded=new AtomicInteger();var failures=new java.util.concurrent.ConcurrentLinkedQueue<String>();
        try(var pool=Executors.newFixedThreadPool(8)) {
            List<Future<?>> tasks=new ArrayList<>();
            for(int i=0;i<8;i++){int n=i;tasks.add(pool.submit(()->{
                try {assertTrue(start.await(5,TimeUnit.SECONDS));tx.executeWithoutResult(status->users.insert("distinct-"+n,"1380000000"+n,"unused",0,20,NOW));succeeded.incrementAndGet();}
                catch(org.springframework.dao.DataAccessException failure){failures.add(failure.getClass().getSimpleName());}
                catch(InterruptedException failure){throw new RuntimeException(failure);}
            }));}
            start.countDown();for(var task:tasks)task.get(15,TimeUnit.SECONDS);
        } finally {start.countDown();}
        assertEquals(8,succeeded.get(),"every distinct account must commit; failures="+failures);
        assertEquals(8,db.queryForObject("SELECT COUNT(*) FROM users",Integer.class));
        assertEquals(8*66,db.queryForObject("SELECT COUNT(*) FROM user_phone_search",Integer.class));
    }

    @Test void interruptedKeyMigrationRetainsUnreadableCiphertextAndResumesAfterTheOldKeyIsSupplied() {
        var legacy=new UserDao(db).insert("first-legacy","13800138998","unused",0,20,NOW);
        String oldKey=key();var oldCrypto=new PersonalDataCrypto(oldKey,index,"",new ObjectMapper());
        var oldUser=tx.execute(status->new UserDao(db,oldCrypto).insert("needs-old-key","13800138999","unused",0,35,NOW));
        String before=db.queryForObject("SELECT phone_encrypted FROM users WHERE id=?",String.class,oldUser.id());
        assertThrows(com.example.takeout.common.BizException.class,()->migration(crypto).run(new DefaultApplicationArguments()));
        assertEquals(before,db.queryForObject("SELECT phone_encrypted FROM users WHERE id=?",String.class,oldUser.id()),"an unreadable row must never be cleared or replaced");
        assertEquals(legacy.phone(),users.findById(legacy.id()).orElseThrow().phone(),"already committed batches remain readable");
        migration(new PersonalDataCrypto(secret,index,oldKey,new ObjectMapper())).run(new DefaultApplicationArguments());
        assertEquals(oldUser.phone(),users.findById(oldUser.id()).orElseThrow().phone());
        assertEquals(55,db.queryForObject("SELECT SUM(balance) FROM users",Integer.class));
        assertEquals(2,db.queryForObject("SELECT COUNT(*) FROM users",Integer.class));
    }
}
