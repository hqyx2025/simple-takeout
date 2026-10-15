package com.example.takeout.service;

public interface SmsCodeVerifier {
    void consume(String phone, String code);
}
