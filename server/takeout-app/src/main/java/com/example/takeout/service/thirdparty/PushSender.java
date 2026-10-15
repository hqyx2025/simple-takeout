package com.example.takeout.service.thirdparty;

public interface PushSender {
    void send(String deviceToken, String profileId, String title, String body);
}
