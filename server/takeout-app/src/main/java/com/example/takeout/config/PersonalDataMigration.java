package com.example.takeout.config;

import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.RiderDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.service.PersonalDataCrypto;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.function.LongConsumer;

/** Resumable row transactions. A failed row keeps its source data and prevents readiness. */
@Component
@Order(500)
public class PersonalDataMigration implements ApplicationRunner {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate tx;
    private final PersonalDataCrypto crypto;
    private final UserDao users;
    private final AddressDao addresses;
    private final RiderDao riders;

    public PersonalDataMigration(JdbcTemplate jdbc, TransactionTemplate tx, PersonalDataCrypto crypto,
                                 UserDao users, AddressDao addresses, RiderDao riders) {
        this.jdbc=jdbc; this.tx=tx; this.crypto=crypto; this.users=users; this.addresses=addresses; this.riders=riders;
    }

    @Override public void run(ApplicationArguments args) {
        String fingerprint = crypto.hash("index-key-check", "takeout-personal-data-v1");
        jdbc.update("INSERT INTO personal_data_key_state(id,index_check) VALUES(1,?) ON DUPLICATE KEY UPDATE id=id", fingerprint);
        if (!fingerprint.equals(jdbc.queryForObject("SELECT index_check FROM personal_data_key_state WHERE id=1", String.class))) {
            throw new IllegalStateException("个人资料检索密钥发生变化；须在维护窗口按旧密钥读取并重建索引，禁止直接替换");
        }
        scan("users", users::reencryptPhone);
        scan("addresses", addresses::reencrypt);
        scan("riders", riders::reencrypt);
        scan("orders", id -> {
            String stored = jdbc.queryForObject("SELECT address FROM orders WHERE id=? FOR UPDATE", String.class, id);
            if (!crypto.isCurrent(stored)) jdbc.update("UPDATE orders SET address=? WHERE id=?",
                    crypto.encrypt(crypto.readLegacy(stored, "orders.address"), "orders.address"), id);
        });
    }

    private void scan(String table, LongConsumer migrate) {
        long cursor = 0;
        while (true) {
            // Table names are fixed callers above, never request input.
            List<Long> ids = jdbc.queryForList("SELECT id FROM " + table + " WHERE id>? ORDER BY id LIMIT 200", Long.class, cursor);
            if (ids.isEmpty()) return;
            for (long id : ids) tx.executeWithoutResult(status -> migrate.accept(id));
            cursor = ids.getLast();
        }
    }
}
