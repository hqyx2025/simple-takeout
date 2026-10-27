package com.example.takeout.common;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

public final class IntegrationSecret {
    private IntegrationSecret() {}
    public static void require(String expected, String supplied) {
        if (expected == null || expected.length() < 32 || supplied == null ||
                !MessageDigest.isEqual(expected.getBytes(StandardCharsets.UTF_8), supplied.getBytes(StandardCharsets.UTF_8))) {
            throw new BizException(403, "无权访问内部接口");
        }
    }
}
