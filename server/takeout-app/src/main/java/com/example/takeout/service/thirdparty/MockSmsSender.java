package com.example.takeout.service.thirdparty;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Value;

/** Local-only SMS sender. It intentionally does not log phone numbers or codes. */
@Service
@ConditionalOnProperty(name = "takeout.sms.provider", havingValue = "mock", matchIfMissing = true)
public class MockSmsSender implements SmsSender {

    private final boolean exposeCode;

    public MockSmsSender(@Value("${takeout.sms.expose-mock-code:false}") boolean exposeCode) {
        this.exposeCode = exposeCode;
    }

    @Override
    public void sendSmsCode(String phone, String code) {
        // No transport in local mock mode.
    }

    @Override
    public boolean exposesCodeForDevelopment() {
        return exposeCode;
    }
}
