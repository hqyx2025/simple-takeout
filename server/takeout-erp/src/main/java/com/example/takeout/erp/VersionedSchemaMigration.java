package com.example.takeout.erp;

import org.flywaydb.core.Flyway;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.flyway.autoconfigure.FlywayMigrationStrategy;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;

@Configuration(proxyBeanMethods = false)
public class VersionedSchemaMigration {
    @Bean
    FlywayMigrationStrategy deferUntilLegacySchemaIsReady() {
        return flyway -> { /* erp-schema.sql and document-number upgrade run before the versioned baseline. */ };
    }

    @Bean
    @Order(300)
    ApplicationRunner migrateVersionedSchema(Flyway flyway) {
        return args -> flyway.migrate();
    }
}
