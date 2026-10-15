package com.example.takeout.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertThrows;

class HuaweiObsStorageServiceTest {

    @Test
    void rejectsMissingCredentialsAndPublicEndpointAtStartup() {
        assertThrows(IllegalStateException.class,
                () -> new HuaweiObsStorageService("https://obs.cn-north-4.myhuaweicloud.com", "bucket",
                        "access", "", "https://cdn.example.com"));
        assertThrows(IllegalStateException.class,
                () -> new HuaweiObsStorageService("http://obs.cn-north-4.myhuaweicloud.com", "bucket",
                        "access", "secret", "https://cdn.example.com"));
    }
}
