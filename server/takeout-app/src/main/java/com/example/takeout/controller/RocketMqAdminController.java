package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.common.CrudOperation;
import com.example.takeout.common.RequireCrud;
import com.example.takeout.service.mq.RocketMqOperations;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/admin/mq")
public class RocketMqAdminController {
    private final ObjectProvider<RocketMqOperations> operations;
    private final JdbcTemplate jdbc;

    public RocketMqAdminController(ObjectProvider<RocketMqOperations> operations, JdbcTemplate jdbc) {
        this.operations = operations;
        this.jdbc = jdbc;
    }

    private RocketMqOperations requireAdmin(int role) {
        if (role != 2) throw new BizException(403, "仅管理端可管理消息队列");
        var mq = operations.getIfAvailable();
        if (mq == null) throw new BizException(503, "消息队列未启用");
        return mq;
    }

    @GetMapping
    public ApiResponse<?> status(@RequestAttribute("role") int role) {
        return ApiResponse.ok(requireAdmin(role).snapshot());
    }

    @PostMapping("/dead-letters/replay")
    @RequireCrud({CrudOperation.UPDATE})
    public ApiResponse<?> replay(@RequestAttribute("role") int role, @RequestAttribute("userId") long userId,
                                @RequestParam(defaultValue = "10") int limit) throws Exception {
        var mq = requireAdmin(role);
        if (limit < 1 || limit > 10) throw new BizException(400, "每次可重放 1 至 10 条消息");
        int sent = mq.replayDeadLetters(limit);
        jdbc.update("INSERT INTO operation_audit_logs(operator_id,operator_role,action,http_method,request_path,outcome,http_status,created_at) "
                        + "VALUES(?,2,'MQ_DLQ_REPLAY','POST','/api/admin/mq/dead-letters/replay','SUCCESS',200,?)",
                userId, System.currentTimeMillis());
        return ApiResponse.ok(Map.of("replayed", sent));
    }
}
