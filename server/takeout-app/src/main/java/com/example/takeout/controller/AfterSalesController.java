package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.model.RefundRecord;
import com.example.takeout.service.AfterSalesService;
import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api")
public class AfterSalesController {
    private final AfterSalesService service;
    public AfterSalesController(AfterSalesService service) { this.service = service; }

    @GetMapping("/merchant/orders/{id}/refunds")
    public ApiResponse<List<RefundRecord>> merchantRefunds(@RequestAttribute("userId") long userId,
                                                          @RequestAttribute("role") int role, @PathVariable long id) {
        requireMerchant(role);
        return ApiResponse.ok(service.merchantHistory(userId, id));
    }

    @PostMapping("/after-sales/{refundId}/merchant-evidence")
    public ApiResponse<RefundRecord> evidence(@RequestAttribute("userId") long userId,
                                               @RequestAttribute("role") int role, @PathVariable long refundId,
                                               @RequestBody EvidenceRequest request) {
        requireMerchant(role);
        return ApiResponse.ok(service.merchantEvidence(userId, refundId, request.response(), request.evidenceImages()));
    }

    @GetMapping("/merchant/after-sales/ledger")
    public ApiResponse<AfterSalesService.LedgerPage> ledger(@RequestAttribute("userId") long userId,
                                                            @RequestAttribute("role") int role,
                                                            @RequestParam(defaultValue="1") int page,
                                                            @RequestParam(defaultValue="20") int pageSize) {
        requireMerchant(role);
        return ApiResponse.ok(service.merchantLedger(userId, page, pageSize));
    }

    public record EvidenceRequest(String response, List<String> evidenceImages) {}
    private static void requireMerchant(int role) {
        if (role != 1) throw new BizException(403, "仅商户可以执行该操作");
    }
}
