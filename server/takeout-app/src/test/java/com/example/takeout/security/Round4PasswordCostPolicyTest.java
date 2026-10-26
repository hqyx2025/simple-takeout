package com.example.takeout.security;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.service.AuthService;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round4PasswordCostPolicyTest {
    @Test void aboveCanonicalCostRequiresRecoveryAndDoesNotRunTheExpensiveVerifier() throws Exception {
        String high = highCostHash("known-password", 1_800_000);
        String modern = PasswordUtil.hash("known-password");
        assertTrue(PasswordUtil.matches("known-password", high), "fixture must be a valid higher-cost hash");
        var normalTimes = new ArrayList<Long>(); var highTimes = new ArrayList<Long>();
        for (int i = 0; i < 2; i++) { PasswordUtil.matchesForLogin("wrong", modern); PasswordUtil.matchesForLogin("wrong", high); }
        for (int i = 0; i < 5; i++) {
            long start = System.nanoTime(); PasswordUtil.matchesForLogin("wrong", modern); normalTimes.add(System.nanoTime() - start);
            start = System.nanoTime(); PasswordUtil.matchesForLogin("wrong", high); highTimes.add(System.nanoTime() - start);
        }
        boolean accepted = PasswordUtil.matchesForLogin("known-password", high);
        double normal = median(normalTimes) / 1e6, imported = median(highTimes) / 1e6;
        System.out.printf(Locale.ROOT, "[RT-25] canonical=%.2fms imported-1800000=%.2fms correct-imported-accepted=%s%n", normal, imported, accepted);
        assertFalse(accepted, "unsupported hash must require existing password recovery, never silently lower the hash");
        assertTrue(Math.abs(imported - normal) / Math.max(imported, normal) < .10);
        assertTrue(PasswordUtil.matchesForLogin("known-password", modern));
    }
    @Test void httpBoundaryOwnsLengthPolicyAndPrimitiveDoesNotRepeatIt() {
        String oversized = "p".repeat(65);
        var users = mock(UserDao.class); var auth = new AuthService(users, mock(JwtUtil.class));
        assertEquals(400, assertThrows(BizException.class, () -> auth.login("13800138000", oversized)).getCode());
        verifyNoInteractions(users);
        String hash = PasswordUtil.hash(oversized);
        assertTrue(PasswordUtil.matchesForLogin(oversized, hash));
        assertFalse(PasswordUtil.matchesForLogin(null, hash));
        System.out.println("[RT-25] oversized HTTP password rejected before lookup; primitive has no duplicate length policy");
    }
    private static long median(List<Long> values) { return values.stream().sorted().toList().get(values.size() / 2); }
    private static String highCostHash(String raw, int iterations) throws Exception {
        byte[] salt = new byte[16]; new java.security.SecureRandom().nextBytes(salt);
        var spec = new javax.crypto.spec.PBEKeySpec(raw.toCharArray(), salt, iterations, 256);
        try {
            byte[] key = javax.crypto.SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
            return "pbkdf2-sha256$" + iterations + "$" + HexFormat.of().formatHex(salt) + "$" + HexFormat.of().formatHex(key);
        } finally { spec.clearPassword(); }
    }
}
