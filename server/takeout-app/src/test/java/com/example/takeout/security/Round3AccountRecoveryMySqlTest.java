package com.example.takeout.security;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import java.nio.file.*;
import java.net.*;
import java.net.http.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.TimeUnit;
import static org.junit.jupiter.api.Assertions.*;

/** This is a drill of an accepted lockout risk, not a claim that targeted lockout is fixed. */
@EnabledIfEnvironmentVariable(named = "TAKEOUT_MYSQL_CONCURRENCY_TEST", matches = "1")
@EnabledIfEnvironmentVariable(named = "TAKEOUT_TEST_REDIS_PORT", matches = "\\d+")
class Round3AccountRecoveryMySqlTest {
    @TempDir Path working;
    private Process process;
    private final HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
    private final String phone = "13999990001";
    private final String correct = "isolated-recovery-password";
    private Path output;
    private int port;
    private Map<String, String> env;

    @Test void actualAppRestartAfterExactRedisClearRestoresAdminButKeepsOffenderBlocked() throws Exception {
        String database = "takeout_recovery_" + UUID.randomUUID().toString().replace("-", "");
        String base = "jdbc:mysql://" + System.getenv().getOrDefault("TAKEOUT_DB_HOST", "127.0.0.1")
                + ":" + System.getenv("TAKEOUT_DB_PORT") + "/";
        String options = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai";
        var admin = new JdbcTemplate(new DriverManagerDataSource(base + options, "root", System.getenv("TAKEOUT_DB_PASSWORD")));
        var connection = new LettuceConnectionFactory("127.0.0.1", Integer.parseInt(System.getenv("TAKEOUT_TEST_REDIS_PORT")));
        connection.afterPropertiesSet(); connection.start();
        var redis = new StringRedisTemplate(connection);
        long userId = 1_000_000_000L + Math.floorMod(System.nanoTime(), 1_000_000_000L);
        String accountKey = "takeout:rl:login-account-fail:u" + userId;
        var accountKeys = java.util.stream.Stream.of("login-account", "login-account-fail", "login-account-total")
                .flatMap(action -> java.util.stream.Stream.of("takeout:rl:" + action + ":u" + userId,
                        "takeout:rl:" + action + ":u" + userId + ":blocked")).toList();
        List<String> warmupKeys = new ArrayList<>();
        String attacker = "198.51.100.179", owner = "192.0.2.179";
        try {
            admin.execute("CREATE DATABASE `" + database + "`");
            var source = new DriverManagerDataSource(base + database + options, "root", System.getenv("TAKEOUT_DB_PASSWORD"));
            new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(source);
            new JdbcTemplate(source).update("INSERT INTO users(id,username,phone,password,role,status,create_time) VALUES(?,?,?, ?,2,1,'2026-10-25 00:00:00')",
                    userId, "isolated-admin", phone, PasswordUtil.hash(correct));
            try (var socket = new java.net.ServerSocket(0, 0, InetAddress.getLoopbackAddress())) { port = socket.getLocalPort(); }
            output = Path.of("../../TemporaryCacheStorage/round3-defense").toAbsolutePath().normalize(); Files.createDirectories(output);
            env = new HashMap<>(System.getenv());
            env.put("TAKEOUT_ERP_ENABLED","false"); // This isolated auth child deliberately disables Outbox and downstream services.
            // Use only the test DB/Redis; never read .env or contact SMTP/payment providers.
            env.put("SPRING_PROFILES_ACTIVE", "develop"); env.put("SPRING_DATASOURCE_URL", base + database + options);
            env.put("SPRING_DATASOURCE_USERNAME", "root"); env.put("SPRING_DATASOURCE_PASSWORD", System.getenv("TAKEOUT_DB_PASSWORD"));
            env.put("TAKEOUT_REDIS_HOST", "127.0.0.1"); env.put("TAKEOUT_REDIS_PORT", System.getenv("TAKEOUT_TEST_REDIS_PORT"));
            env.put("TAKEOUT_REDIS_USERNAME", ""); env.put("TAKEOUT_REDIS_PASSWORD", "");
            env.put("TAKEOUT_SMS_PROVIDER", "qq-email"); env.put("TAKEOUT_QQ_SMTP_USERNAME", "test@example.invalid");
            env.put("TAKEOUT_QQ_SMTP_AUTH_CODE", "not-used-no-mail-sent"); env.put("TAKEOUT_DATA_SEED_ENABLED", "false");
            env.put("TAKEOUT_CACHE_ENABLED", "false"); env.put("TAKEOUT_MQ_ENABLED", "false");
            env.put("TAKEOUT_LOG_DIR", output.resolve("recovery-child-logs").toString());
            for (String key : List.of("TAKEOUT_JWT_SECRET", "TAKEOUT_VERIFICATION_HMAC_SECRET", "TAKEOUT_ASSISTANT_ENCRYPTION_SECRET", "TAKEOUT_WALLET_ENCRYPTION_SECRET")) {
                byte[] bytes = new byte[32]; new java.security.SecureRandom().nextBytes(bytes); env.put(key, Base64.getEncoder().encodeToString(bytes));
            }
            start("before"); long beforePid = process.pid();
            awaitDistributedLoginBudgets(redis, warmupKeys);
            for (int i = 0; i < 10; i++) assertEquals(400, login(attacker, "wrong-password"));
            assertEquals(429, login(owner, correct));
            assertTrue(Boolean.TRUE.equals(redis.hasKey(accountKey + ":blocked")));
            redis.delete(accountKeys);
            assertEquals(429, login(owner, correct), "Redis-only clear cannot remove the app's local mirror");
            stop(); start("after");
            redis.delete(warmupKeys); warmupKeys.clear();
            awaitDistributedLoginBudgets(redis, warmupKeys);
            assertNotEquals(beforePid, process.pid());
            assertEquals(200, login(owner, correct));
            assertEquals(429, login(attacker, "wrong-password"));
            System.out.println("[RT-16 accepted/drill] wrong=10 other-source-admin=429 Redis-only-clear=429 process-restart-admin=200 offender=429 pid-changed=true");
            System.out.println("[RT-16 accepted/drill] account-global-lockout-remains=true production-account-untouched=true");
        } finally {
            stop();
            redis.delete(accountKeys);
            if (!warmupKeys.isEmpty()) redis.delete(warmupKeys);
            redis.delete(List.of(accountKey, accountKey + ":blocked", "takeout:rl:login:" + attacker,
                    "takeout:rl:login:" + attacker + ":blocked", "takeout:rl:login-total:" + attacker,
                    "takeout:rl:login-total:" + attacker + ":blocked", "takeout:rl:login-total:" + owner,
                    "takeout:rl:login-total:" + owner + ":blocked"));
            connection.destroy(); admin.execute("DROP DATABASE IF EXISTS `" + database + "`");
        }
    }
    private void start(String phase) throws Exception {
        String executable = System.getProperty("os.name").toLowerCase(Locale.ROOT).startsWith("windows") ? "java.exe" : "java";
        String java = Path.of(System.getProperty("java.home"), "bin", executable).toString();
        var builder = new ProcessBuilder(java, "-cp", System.getProperty("surefire.test.class.path", System.getProperty("java.class.path")),
                "com.example.takeout.TakeoutApplication", "--server.address=127.0.0.1", "--server.port=" + port,
                "--server.tomcat.protocol=org.apache.coyote.http11.Http11Nio2Protocol", "--takeout.payment.sandbox=false",
                "--takeout.payment.real-enabled=false", "--takeout.payment.mock-enabled=false", "--takeout.upload.local-enabled=true",
                "--takeout.upload.local-path=" + working.resolve("uploads"), "--takeout.order.timeout-scan-initial-ms=3600000");
        builder.directory(working.toFile()); builder.environment().clear(); builder.environment().putAll(env);
        builder.redirectErrorStream(true).redirectOutput(output.resolve("recovery-child-" + phase + ".log").toFile());
        process = builder.start();
        long deadline = System.nanoTime() + Duration.ofSeconds(50).toNanos();
        while (System.nanoTime() < deadline) {
            assertTrue(process.isAlive(), "Isolated child app exited; inspect recovery-child-" + phase + ".log");
            try {
                var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/api/auth/me")).timeout(Duration.ofSeconds(2)).build();
                if (client.send(request, HttpResponse.BodyHandlers.discarding()).statusCode() == 401) return;
            } catch (java.io.IOException ignored) { }
            Thread.sleep(100);
        }
        fail("Isolated child app did not become ready");
    }
    private void awaitDistributedLoginBudgets(StringRedisTemplate redis, List<String> warmupKeys) throws Exception {
        long deadline = System.nanoTime() + Duration.ofSeconds(15).toNanos();
        for (int attempt = 1; attempt <= 254 && System.nanoTime() < deadline; attempt++) {
            String source = "203.0.113." + attempt;
            String failureKey = "takeout:rl:login:" + source;
            String totalKey = "takeout:rl:login-total:" + source;
            warmupKeys.addAll(List.of(failureKey, failureKey + ":blocked", totalKey, totalKey + ":blocked"));
            String warmupPhone = String.format(Locale.ROOT, "1388888%04d", attempt);
            for (String action : List.of("login-account-fail", "login-account-total")) {
                String accountKey = "takeout:rl:" + action + ":unknown:" + warmupPhone;
                warmupKeys.addAll(List.of(accountKey, accountKey + ":blocked"));
            }
            assertEquals(400, login(warmupPhone, source, "isolated-warmup-password"));
            if (Boolean.TRUE.equals(redis.hasKey(failureKey)) && Boolean.TRUE.equals(redis.hasKey(totalKey))) return;
            // Cold connection/script loading can activate the intended five-second local fallback.
            // Start the distributed recovery drill only once this child demonstrably writes Redis.
            Thread.sleep(100);
        }
        fail("Isolated child app did not start recording distributed login budgets");
    }
    private int login(String source, String password) throws Exception {
        return login(phone, source, password);
    }
    private int login(String accountPhone, String source, String password) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/api/auth/login"))
                .timeout(Duration.ofSeconds(10)).header("Content-Type", "application/json").header("X-Forwarded-For", source)
                .POST(HttpRequest.BodyPublishers.ofString("{\"phone\":\"" + accountPhone + "\",\"password\":\"" + password + "\",\"loginType\":\"ADMIN\"}")).build();
        return client.send(request, HttpResponse.BodyHandlers.discarding()).statusCode();
    }
    private void stop() throws Exception {
        if (process == null) return;
        process.destroy(); if (!process.waitFor(10, TimeUnit.SECONDS)) { process.destroyForcibly(); process.waitFor(5, TimeUnit.SECONDS); }
        process = null;
    }
}
