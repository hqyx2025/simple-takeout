package com.example.takeout.service.thirdparty;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

/** Local-only SMS sender. It intentionally does not log phone numbers or codes. */
@Service
@ConditionalOnProperty(name = "takeout.sms.provider", havingValue = "mock", matchIfMissing = true)
public class MockSmsSender implements SmsSender {

    @Override
    public void sendSmsCode(String phone, String code) {
        // No transport in local mock mode.
    }

    @Override
    public boolean exposesCodeForDevelopment() {
        return true;
    }
}
