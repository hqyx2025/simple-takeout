package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.service.AssistantService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 智能助手接口（规则问答，纯只读）。
 * 与其他业务接口口径一致：需要登录，用户身份从 JWT 解析出的 userId 取。
 */
@RestController
@RequestMapping("/api/assistant")
public class AssistantController {

    private final AssistantService assistantService;

    public AssistantController(AssistantService assistantService) {
        this.assistantService = assistantService;
    }

    /** 提问请求体：question 为用户的原始输入。 */
    public record AskRequest(String question) {
    }

    @PostMapping("/chat")
    public ApiResponse<AssistantService.AssistantReply> chat(@RequestAttribute("userId") long userId,
                                                             @RequestBody AskRequest req) {
        return ApiResponse.ok(assistantService.reply(userId, req == null ? "" : req.question()));
    }
}
