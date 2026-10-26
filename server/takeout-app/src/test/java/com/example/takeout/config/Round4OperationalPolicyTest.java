package com.example.takeout.config;

import org.junit.jupiter.api.Test;
import java.nio.file.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class Round4OperationalPolicyTest {
    private final Path root = Path.of("../..");
    @Test void subdomainHstsUsesNinetyDayRollingPolicy() throws Exception {
        String nginx = Files.readString(root.resolve("server/docker/nginx-domain.conf"));
        assertEquals(2, nginx.lines().filter(line -> line.contains("Strict-Transport-Security")
                && line.contains("max-age=7776000; includeSubDomains")).count());
        System.out.println("[RT-24] HTTPS servers with 90-day includeSubDomains policy=2");
    }
    @Test void everyLoginControlIsDiscoverableInReadmeAndEnvironmentExample() throws Exception {
        String readme = Files.readString(root.resolve("README.md"));
        String example = Files.readString(root.resolve(".env.example"));
        List<String> names = List.of("TAKEOUT_LOGIN_FAILURE_LIMIT", "TAKEOUT_LOGIN_FAILURE_WINDOW_SECONDS", "TAKEOUT_LOGIN_FAILURE_BLOCK_SECONDS",
                "TAKEOUT_LOGIN_TOTAL_LIMIT", "TAKEOUT_LOGIN_TOTAL_WINDOW_SECONDS", "TAKEOUT_LOGIN_TOTAL_BLOCK_SECONDS",
                "TAKEOUT_LOGIN_ACCOUNT_LIMIT", "TAKEOUT_LOGIN_ACCOUNT_WINDOW_SECONDS", "TAKEOUT_LOGIN_ACCOUNT_BLOCK_SECONDS",
                "TAKEOUT_LOGIN_ACCOUNT_TOTAL_LIMIT", "TAKEOUT_LOGIN_ACCOUNT_TOTAL_WINDOW_SECONDS", "TAKEOUT_LOGIN_ACCOUNT_TOTAL_BLOCK_SECONDS",
                "TAKEOUT_LOGIN_VERIFY_MAX_CONCURRENT", "TAKEOUT_LOGIN_VERIFY_WAIT_MILLIS");
        for (String name : names) {
            assertTrue(readme.contains("`" + name + "`"), "README missing " + name);
            assertTrue(example.lines().anyMatch(line -> line.startsWith(name + "=")), ".env.example missing " + name);
        }
        assertTrue(readme.contains("全部本地窗口")); assertTrue(readme.contains("Redis 预算"));
        assertTrue(readme.contains("在途请求")); assertTrue(readme.contains("CPU"));
        System.out.println("[RT-22/25] documented login controls=14; restart loss and Redis budget verification stated");
    }
}
