package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.service.FinancialReconciliationService;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/admin/reconciliation")
public class FinancialReconciliationController {
    private final FinancialReconciliationService service;
    public FinancialReconciliationController(FinancialReconciliationService service) { this.service = service; }
    @GetMapping
    public ApiResponse<List<Map<String,Object>>> issues(@RequestAttribute("role") int role,
                                                       @RequestParam(defaultValue="50") int limit) {
        if (role != 2) throw new BizException(403, "仅管理员可以查看对账差异");
        return ApiResponse.ok(service.issues(limit));
    }
}
