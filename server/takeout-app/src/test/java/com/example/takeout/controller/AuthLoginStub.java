package com.example.takeout.controller;

import com.example.takeout.service.AuthService;
import java.util.function.Consumer;
import java.util.function.Function;
import static org.mockito.Mockito.*;

/** Controller-only tests: run admission before the existing stubbed password verifier. */
final class AuthLoginStub {
    static void bind(AuthService auth, Function<String, String> identity) {
        doAnswer(call -> {
            Consumer<String> admit = call.getArgument(3);
            admit.accept(identity.apply(call.getArgument(0)));
            return auth.login(call.getArgument(0), call.getArgument(1), call.getArgument(2));
        }).when(auth).login(anyString(), anyString(), anyString(), any());
    }
}
