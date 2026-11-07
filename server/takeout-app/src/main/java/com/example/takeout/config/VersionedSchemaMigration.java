package com.example.takeout.config;

import org.flywaydb.core.Flyway;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.flyway.autoconfigure.FlywayMigrationStrategy;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;

/** The existing additive upgrades must complete before the first versioned baseline is recorded. */
@Configuration(proxyBeanMethods = false)
public class VersionedSchemaMigration {
    @Bean
    FlywayMigrationStrategy deferUntilLegacySchemaIsReady() {
        return flyway -> { /* schema.sql and the ordered legacy runners still own pre-baseline upgrades. */ };
    }

    @Bean
    @Order(300)
    ApplicationRunner migrateVersionedSchema(Flyway flyway) {
        return args -> flyway.migrate();
    }
}
