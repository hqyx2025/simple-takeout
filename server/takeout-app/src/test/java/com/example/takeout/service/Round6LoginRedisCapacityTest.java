package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.controller.AuthController;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import com.example.takeout.security.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.mock.web.MockHttpServletRequest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class Round6LoginRedisCapacityTest {
    private static final String PASSWORD = "round-six-password";
    private static final String HASH = PasswordUtil.hash(PASSWORD);

    @Test void thirtyValidControllerLoginsSurviveColdFiveHundredMillisecondRedis() throws Exception {
        for (int delay : new int[]{0, 500}) {
            var calls = new AtomicInteger();
            var redis = mock(StringRedisTemplate.class);
            when(redis.hasKey(anyString())).thenAnswer(call -> {
                calls.incrementAndGet(); Thread.sleep(delay); return false;
            });
            when(redis.execute(any(RedisScript.class), anyList(), any(Object[].class))).thenAnswer(call -> {
                calls.incrementAndGet(); Thread.sleep(delay); return 1L;
            });
            ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
            when(provider.getIfAvailable()).thenReturn(redis);
            var limiter = new LoginRateLimiter(provider);
            var users = mock(UserDao.class); var jwt = mock(JwtUtil.class);
            when(users.findByPhone(anyString())).thenAnswer(call -> {
                String phone = call.getArgument(0);
                return Optional.of(new User(Long.parseLong(phone), "probe", "", phone, HASH, 0, 0, "now"));
            });
            when(jwt.generateToken(anyLong(), anyInt(), anyString())).thenReturn("token");
            var auth = new AuthService(users, jwt); auth.afterPropertiesSet();
            for (int i = 0; i < 4; i++) auth.login("13800138000", PASSWORD, "USER");
            var controller = new AuthController(auth, limiter, mock(TokenRevocationService.class),
                    mock(RefreshTokenService.class), mock(SmsVerificationService.class), mock(PushTokenService.class));
            var ready = new CountDownLatch(30); var start = new CountDownLatch(1);
            var codes = new ArrayList<Integer>(); var futures = new ArrayList<Future<Integer>>();
            long elapsed;
            try (var pool = Executors.newFixedThreadPool(30)) {
                for (int i = 0; i < 30; i++) {
                    String phone = "1380013" + String.format(Locale.ROOT, "%04d", i);
                    futures.add(pool.submit(() -> {
                        var request = new MockHttpServletRequest(); request.setRemoteAddr("192.0.2.206");
                        ready.countDown(); start.await();
                        try {
                            controller.login(new AuthController.LoginRequest(phone, PASSWORD, "USER"), request);
                            return 200;
                        } catch (BizException e) { return e.getCode(); }
                    }));
                }
                assertTrue(ready.await(5, TimeUnit.SECONDS)); long begin = System.nanoTime(); start.countDown();
                for (var future : futures) codes.add(future.get(20, TimeUnit.SECONDS));
                elapsed = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - begin);
            }
            System.out.println("[RT-29/controller] redis-ms=" + delay + " burst=30 success="
                    + Collections.frequency(codes, 200) + " busy503=" + Collections.frequency(codes, 503)
                    + " redis-calls=" + calls.get() + " elapsed-ms=" + elapsed);
            assertEquals(30, Collections.frequency(codes, 200), codes.toString());
        }
    }
}
