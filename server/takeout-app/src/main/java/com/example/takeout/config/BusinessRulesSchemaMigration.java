package com.example.takeout.config;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.stereotype.Component;
import javax.sql.DataSource;

/** Additive business facts; safe on both a new database and an existing installation. */
@Component
@org.springframework.core.annotation.Order(200)
public class BusinessRulesSchemaMigration implements ApplicationRunner {
    private final DataSource dataSource;
    public BusinessRulesSchemaMigration(DataSource dataSource) { this.dataSource = dataSource; }
    @Override public void run(ApplicationArguments args) {
        new ResourceDatabasePopulator(new ClassPathResource("business-rules.sql")).execute(dataSource);
        // Existing self-delivery already in transit must remain completable after upgrade.
        new org.springframework.jdbc.core.JdbcTemplate(dataSource).update(
                "INSERT IGNORE INTO order_fulfillment(order_id,mode) SELECT id," +
                "CASE WHEN rider_id=0 AND status IN(3,4,6) THEN 'MERCHANT' ELSE 'RIDER' END FROM orders");
    }
}
