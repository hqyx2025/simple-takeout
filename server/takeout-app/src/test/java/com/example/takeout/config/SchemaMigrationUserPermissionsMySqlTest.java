package com.example.takeout.config;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

@EnabledIfEnvironmentVariable(named="TAKEOUT_MYSQL_CONCURRENCY_TEST", matches="1")
class SchemaMigrationUserPermissionsMySqlTest {
    @Test void migrationPreservesLegacyAccountsAndNeverResetsRevokedPermissions() {
        String base="jdbc:mysql://"+System.getenv().getOrDefault("TAKEOUT_DB_HOST","127.0.0.1")+":"
                +System.getenv().getOrDefault("TAKEOUT_DB_PORT","3310")+"/";
        String options="?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String username=System.getenv().getOrDefault("TAKEOUT_DB_USERNAME","root"), password=System.getenv("TAKEOUT_DB_PASSWORD");
        var admin=new JdbcTemplate(new DriverManagerDataSource(base+options,username,password));
        String schema="takeout_crud_migration_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE `"+schema+"`");
        try {
            var db=new JdbcTemplate(new DriverManagerDataSource(base+schema+options,username,password));
            db.execute("CREATE TABLE users(id BIGINT PRIMARY KEY,username VARCHAR(64) NOT NULL)");
            db.update("INSERT INTO users VALUES(1,'legacy')");
            var migration=new SchemaMigration(db);
            migration.migrateUserCrudPermissions();
            migration.migrateUserCrudPermissions();
            for(String op:new String[]{"create","read","update","delete"}) {
                assertEquals(1,db.queryForObject("SELECT can_"+op+" FROM users WHERE id=1",Integer.class));
                var failure=assertThrows(DataAccessException.class,()->db.update("UPDATE users SET can_"+op+"=2 WHERE id=1"));
                assertEquals(3819,assertInstanceOf(java.sql.SQLException.class,failure.getMostSpecificCause()).getErrorCode());
            }
            db.update("UPDATE users SET can_create=0,can_delete=0 WHERE id=1");
            migration.migrateUserCrudPermissions();
            assertEquals(0,db.queryForObject("SELECT can_create FROM users WHERE id=1",Integer.class));
            assertEquals(0,db.queryForObject("SELECT can_delete FROM users WHERE id=1",Integer.class));
            db.update("INSERT INTO users(id,username) VALUES(2,'new')");
            assertEquals(1,db.queryForObject("SELECT can_read FROM users WHERE id=2",Integer.class));
        } finally { admin.execute("DROP DATABASE `"+schema+"`"); }
    }
}
