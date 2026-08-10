package com.example.takeout.common;

/**
 * 业务异常：业务规则校验失败时抛出，由全局异常处理器统一转换为 ApiResponse
 */
public class BizException extends RuntimeException {

    private final int code;

    public BizException(String message) {
        this(400, message);
    }

    public BizException(int code, String message) {
        super(message);
        this.code = code;
    }

    public int getCode() {
        return code;
    }
}
