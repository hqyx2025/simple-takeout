package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.service.AssistantAiClient;
import com.example.takeout.service.AssistantService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 用户端助手接口；身份由认证拦截器提供，不接受客户端指定用户。
 * 与其他业务接口口径一致：需要登录，用户身份从 JWT 解析出的 userId 取。
 */
@RestController
@RequestMapping("/api/assistant")
public class AssistantController {

    private final AssistantService assistantService;

    public AssistantController(AssistantService assistantService) {
        this.assistantService = assistantService;
    }

    public record AskRequest(String question, List<AssistantAiClient.Message> history) {
    }

    @PostMapping("/chat")
    public ApiResponse<AssistantService.AssistantReply> chat(@RequestAttribute("userId") long userId,
                                                             @RequestAttribute("role") int role,
                                                             @RequestBody AskRequest req) {
        if (role != 0) {
            throw new BizException(403, "仅用户身份可使用个人助手");
        }
        return ApiResponse.ok(assistantService.reply(userId, req == null ? "" : req.question(),
                req == null ? List.of() : req.history()));
    }
}
