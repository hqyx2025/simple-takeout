package com.example.takeout.service.thirdparty;

/** SMS transport. The OTP is generated and validated by the server. */
public interface SmsSender {
    void sendSmsCode(String phone, String code);

    /** Carries the server-owned recovery identity so email can describe the target and purpose. */
    default void sendVerificationCode(String destination, String code, String identity) {
        sendSmsCode(destination, code);
    }

    /** Only the local development sender may return its generated code to the caller. */
    default boolean exposesCodeForDevelopment() {
        return false;
    }
}
