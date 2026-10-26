package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.*;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round3LoginPrivacyTest {
    private static final String HASH = PasswordUtil.hash("known-strong-password");
    private final UserDao users = mock(UserDao.class);
    private final JwtUtil jwt = mock(JwtUtil.class);
    private final AuthService auth = new AuthService(users, jwt);
    private User user(String phone, int status, String hash) {
        return new User(7, "test", "", phone, hash, 0, status, 0, "now", "");
    }
    private BizException reject(String phone, String password) {
        return assertThrows(BizException.class, () -> auth.login(phone, password, "USER"));
    }
    @Test void nonexistentDisabledAndWrongPasswordHaveTheSamePublicFailure() {
        when(users.findByPhone("13800138000")).thenReturn(Optional.of(user("13800138000", 1, HASH)));
        when(users.findByPhone("13800138001")).thenReturn(Optional.of(user("13800138001", 0, HASH)));
        for (String phone : List.of("13800138000", "13800138001", "13800138002")) {
            var error = reject(phone, "wrong-password");
            assertEquals(400, error.getCode()); assertEquals("账号或密码错误", error.getMessage());
        }
        assertEquals("账号或密码错误", reject("13800138001", "known-strong-password").getMessage());
        verifyNoInteractions(jwt);
        System.out.println("[RT-18] missing/disabled/wrong-password -> identical code=400 and message; disabled token=0");
    }
    @Test void missingDisabledLegacyAndMalformedRowsDoNotSkipThePasswordWork() {
        when(users.findByPhone("13800138000")).thenReturn(Optional.of(user("13800138000", 1, HASH)));
        when(users.findByPhone("13800138001")).thenReturn(Optional.of(user("13800138001", 0, HASH)));
        when(users.findByPhone("13800138003")).thenReturn(Optional.of(user("13800138003", 1, "b86af4172288a2cd465eedefe52f92400e1ae6ad620609a340505ad63b4519cd")));
        when(users.findByPhone("13800138004")).thenReturn(Optional.of(user("13800138004", 1, "broken-hash")));
        for (int i = 0; i < 3; i++) reject("13800138000", "wrong-password");
        var elapsed = new LinkedHashMap<String, List<Long>>();
        for (String phone : List.of("13800138000", "13800138001", "13800138002", "13800138003", "13800138004")) elapsed.put(phone, new ArrayList<>());
        for (int sample = 0; sample < 5; sample++) for (var entry : elapsed.entrySet()) {
            long start = System.nanoTime(); reject(entry.getKey(), "wrong-password");
            entry.getValue().add(System.nanoTime() - start);
        }
        double baseline = median(elapsed.get("13800138000"));
        elapsed.forEach((phone, samples) -> {
            double measured = median(samples);
            System.out.printf(java.util.Locale.ROOT, "[RT-18] phone-suffix=%s median=%.1fms ratio=%.2f%n", phone.substring(9), measured / 1e6, measured / baseline);
        });
        elapsed.forEach((phone, samples) -> assertTrue(median(samples) >= baseline * .55,
                "credential lookup must not skip PBKDF2 work: " + phone));
    }
    private static long median(List<Long> values) { return values.stream().sorted().toList().get(values.size() / 2); }
}
