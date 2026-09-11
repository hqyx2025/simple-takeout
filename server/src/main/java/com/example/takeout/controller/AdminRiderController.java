package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.model.Rider;
import com.example.takeout.service.RiderService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 管理端骑手管理（四端改造）：骑手列表与启停。要求 role=2（ADMIN）。
 */
@RestController
@RequestMapping("/api/admin/riders")
public class AdminRiderController {

    private final RiderService riderService;

    public AdminRiderController(RiderService riderService) {
        this.riderService = riderService;
    }

    @GetMapping
    public ApiResponse<List<Rider>> list(@RequestAttribute("role") int role) {
        requireAdmin(role);
        return ApiResponse.ok(riderService.listAll());
    }

    @PutMapping("/{id}/status")
    public ApiResponse<Rider> updateStatus(@RequestAttribute("role") int role,
                                           @PathVariable long id,
                                           @RequestBody RiderStatusRequest req) {
        requireAdmin(role);
        return ApiResponse.ok(riderService.updateStatus(id, req.status()));
    }

    public record RiderStatusRequest(int status) {
    }

    private void requireAdmin(int role) {
        if (role != 2) {
            throw new BizException(403, "仅平台管理员可以执行该操作");
        }
    }
}
