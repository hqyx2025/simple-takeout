package com.example.takeout.erp;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

import static org.junit.jupiter.api.Assertions.*;

@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
class VersionedSchemaMigrationMySqlTest {
    @Test void bothFreshAndLegacyErpSchemasStartTwiceWithoutLosingHistoricalDocuments() {
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1") + ":"
                + System.getenv().getOrDefault("TAKEOUT_DB_PORT", "3310") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        String user = System.getenv().getOrDefault("TAKEOUT_DB_USERNAME", "root");
        String password = System.getenv("TAKEOUT_DB_PASSWORD");
        var admin = new JdbcTemplate(new DriverManagerDataSource(base + options, user, password));
        for (boolean legacy : new boolean[]{false, true}) {
            String schema = "takeout_erp_versioned_" + java.util.UUID.randomUUID().toString().replace("-", "");
            admin.execute("CREATE DATABASE `" + schema + "`");
            try {
                var source = new DriverManagerDataSource(base + schema + options, user, password);
                var db = new JdbcTemplate(source);
                if (legacy) {
                    new ResourceDatabasePopulator(new ClassPathResource("erp-schema.sql")).execute(source);
                    db.execute("ALTER TABLE erp_purchases DROP INDEX uk_erp_purchases_document_no, DROP COLUMN document_no");
                    db.update("INSERT INTO erp_purchases(id,store_id,supplier_id,operator_id) VALUES(123,10,20,99)");
                }
                for (int start = 0; start < 2; start++) {
                    try (var context = new SpringApplicationBuilder(ErpApplication.class).run("--server.port=0",
                            "--server.address=127.0.0.1", "--management.server.port=0", "--spring.datasource.url=" + base + schema + options,
                            "--spring.datasource.username=" + user, "--spring.datasource.password=" + password,
                            "--takeout.erp.integration-secret=" + "test-only-separate-integration-key-32",
                            "--takeout.erp.app-uri=http://127.0.0.1:1")) {
                        assertEquals(1, db.queryForObject("SELECT COUNT(*) FROM flyway_schema_history WHERE version='1' AND success=1", Integer.class));
                        context.getBean(Flyway.class).validate();
                        if (legacy) assertEquals("CG-L-123", db.queryForObject("SELECT document_no FROM erp_purchases WHERE id=123", String.class));
                    }
                }
            } finally { admin.execute("DROP DATABASE `" + schema + "`"); }
        }
    }
}
