package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.service.AssistantAiClient;
import com.example.takeout.service.AssistantConfigService;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/admin/assistant")
public class AdminAssistantController {
    private final AssistantConfigService configService;
    private final AssistantAiClient aiClient;

    public AdminAssistantController(AssistantConfigService configService, AssistantAiClient aiClient) {
        this.configService = configService;
        this.aiClient = aiClient;
    }

    @GetMapping("/config")
    public ApiResponse<AssistantConfigService.View> config(@RequestAttribute("role") int role) {
        requireAdmin(role);
        return ApiResponse.ok(configService.view());
    }

    @PutMapping("/config")
    public ApiResponse<AssistantConfigService.View> save(@RequestAttribute("role") int role,
                                                        @RequestBody AssistantConfigService.SaveRequest request) {
        requireAdmin(role);
        return ApiResponse.ok(configService.save(request));
    }

    @PostMapping("/test")
    public ApiResponse<String> test(@RequestAttribute("role") int role) {
        requireAdmin(role);
        aiClient.complete(configService.load(), "请回复连接成功", List.of());
        return ApiResponse.ok("连接成功");
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Void>> invalidBody() {
        // Jackson 的解析错误可能包含密钥 token，不交给记录异常文本的全局处理器。
        return ResponseEntity.badRequest().body(ApiResponse.error(400, "请求参数格式不正确"));
    }

    private static void requireAdmin(int role) {
        if (role != 2) {
            throw new BizException(403, "仅平台管理员可以执行该操作");
        }
    }
}
