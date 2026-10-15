package com.example.takeout.service.thirdparty;

/** SMS transport. The OTP is generated and validated by the server. */
public interface SmsSender {
    void sendSmsCode(String phone, String code);

    /** Only the local development sender may return its generated code to the caller. */
    default boolean exposesCodeForDevelopment() {
        return false;
    }
}
