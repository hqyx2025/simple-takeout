package com.example.takeout.security;

import com.example.takeout.common.BizException;
import com.example.takeout.controller.OrderController;
import com.example.takeout.controller.UserCenterController;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.User;
import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.method.HandlerMethod;

import java.util.Arrays;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class UserCrudAuthorizationTest {
    private final JwtUtil jwt = mock(JwtUtil.class);
    private final UserDao users = mock(UserDao.class);
    private final AuthInterceptor auth = new AuthInterceptor(jwt, users, mock(TokenRevocationService.class));

    private User user(boolean create, boolean read, boolean update, boolean delete) {
        return new User(7, "account", "", "13800000007", "", 0, 1, 0, "now", "", "", "",
                create, read, update, delete);
    }

    private void current(User user) {
        var claims = mock(Claims.class);
        when(jwt.parseToken("same-token")).thenReturn(claims);
        when(jwt.getUserId(claims)).thenReturn(7L);
        when(jwt.getRole(claims)).thenReturn(0);
        when(users.findById(7)).thenReturn(Optional.of(user));
    }

    private boolean request(String method, String path, Object handler) {
        var request = new MockHttpServletRequest(method, "/takeout" + path);
        request.setContextPath("/takeout");
        request.addHeader("Authorization", "Bearer same-token");
        return auth.preHandle(request, new MockHttpServletResponse(), handler);
    }

    private HandlerMethod handler(Class<?> type, String name) {
        return new HandlerMethod(mock(type), Arrays.stream(type.getDeclaredMethods())
                .filter(method -> method.getName().equals(name)).findFirst().orElseThrow());
    }

    @Test void eachCrudFlagIsIndependentAndRevocationAppliesToTheSameTokenImmediately() {
        String[] methods = {"POST", "GET", "PUT", "DELETE"};
        for (int i = 0; i < 4; i++) {
            boolean[] flags = {true, true, true, true};
            flags[i] = false;
            current(user(flags[0], flags[1], flags[2], flags[3]));
            String deniedMethod = methods[i];
            assertEquals(403, assertThrows(BizException.class,
                    () -> request(deniedMethod, "/api/addresses", new Object())).getCode());
            for (int j = 0; j < 4; j++) if (j != i) assertTrue(request(methods[j], "/api/addresses", new Object()));
            current(user(true, true, true, true));
            assertTrue(request(methods[i], "/api/addresses", new Object()));
        }
    }

    @Test void postActionsUseBusinessPermissionRatherThanCreatePermission() {
        current(user(false, true, true, false));
        assertTrue(request("POST", "/api/orders/1/pay", handler(OrderController.class, "pay")));
        assertTrue(request("POST", "/api/wallet/bank-cards/1/reveal", handler(UserCenterController.class, "revealBankCard")));
        current(user(true, true, false, true));
        assertEquals(403, assertThrows(BizException.class,
                () -> request("POST", "/api/orders/1/pay", handler(OrderController.class, "pay"))).getCode());
    }

    @Test void safeUserViewNeverResetsDeniedPermissions() {
        User safe = user(false, false, false, false).safe();
        assertFalse(safe.canCreate());
        assertFalse(safe.canRead());
        assertFalse(safe.canUpdate());
        assertFalse(safe.canDelete());
    }
}
