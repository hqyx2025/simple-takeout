package com.example.takeout.config;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST", matches="1")
class SchemaMigrationStoreReviewMySqlTest {
    @Test void legacyAdmissionIsPreservedNewRowsArePendingAndRestartNeverResetsDecisions() {
        String base="jdbc:mysql://"+System.getenv().getOrDefault("TAKEOUT_DB_HOST","127.0.0.1")+":"
                +System.getenv().getOrDefault("TAKEOUT_DB_PORT","3310")+"/";
        String options="?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user=System.getenv().getOrDefault("TAKEOUT_DB_USERNAME","root"), password=System.getenv("TAKEOUT_DB_PASSWORD");
        var admin=new JdbcTemplate(new DriverManagerDataSource(base+options,user,password));
        String schema="takeout_review_migration_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE `"+schema+"`");
        try {
            var db=new JdbcTemplate(new DriverManagerDataSource(base+schema+options,user,password));
            db.execute("CREATE TABLE stores(id BIGINT PRIMARY KEY,status INT NOT NULL)");
            db.update("INSERT INTO stores VALUES(1,1),(2,0)");
            var migration=new SchemaMigration(db);
            migration.migrateStoreReview();
            assertEquals(2,db.queryForObject("SELECT COUNT(*) FROM stores WHERE review_status=1 AND platform_status=1",Integer.class));
            assertEquals(0,db.queryForObject("SELECT status FROM stores WHERE id=2",Integer.class));
            db.update("UPDATE stores SET review_status=2,platform_status=0,review_reason='资料不完整' WHERE id=1");
            migration.migrateStoreReview();
            assertEquals(2,db.queryForObject("SELECT review_status FROM stores WHERE id=1",Integer.class));
            assertEquals(0,db.queryForObject("SELECT platform_status FROM stores WHERE id=1",Integer.class));
            assertEquals("资料不完整",db.queryForObject("SELECT review_reason FROM stores WHERE id=1",String.class));
            db.update("INSERT INTO stores(id,status) VALUES(3,1)");
            assertEquals(0,db.queryForObject("SELECT review_status FROM stores WHERE id=3",Integer.class));
        } finally { admin.execute("DROP DATABASE `"+schema+"`"); }
    }
}
