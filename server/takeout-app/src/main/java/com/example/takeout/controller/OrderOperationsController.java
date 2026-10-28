package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.service.OrderOperationsService;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class OrderOperationsController {
    private final OrderOperationsService operations;
    public OrderOperationsController(OrderOperationsService operations) { this.operations=operations; }
    public record ModeRequest(String mode) {}
    public record IssueRequest(String type,String note,String idempotencyKey) {}
    public record ResolveRequest(String action,String note) {}

    @GetMapping("/merchant/stores/{store}/fulfillment")
    public ApiResponse<Map<String,String>> mode(@RequestAttribute("userId") long user,@RequestAttribute("role") int role,@PathVariable long store) {
        return ApiResponse.ok(operations.readStoreMode(user,role,store));
    }
    @PutMapping("/merchant/stores/{store}/fulfillment")
    public ApiResponse<Map<String,String>> setMode(@RequestAttribute("userId") long user,@RequestAttribute("role") int role,
                                                  @PathVariable long store,@RequestBody ModeRequest request) {
        return ApiResponse.ok(operations.setStoreMode(user,role,store,request.mode()));
    }
    @GetMapping({"/orders/{id}/issues","/merchant/orders/{id}/issues","/rider/orders/{id}/issues"})
    public ApiResponse<List<OrderOperationsService.DeliveryIssue>> issues(@RequestAttribute("userId") long user,
            @RequestAttribute("role") int role,@PathVariable long id,jakarta.servlet.http.HttpServletRequest request) {
        requireOrderRoute(role, request.getRequestURI());
        return ApiResponse.ok(operations.issues(user,role,id));
    }
    @PostMapping({"/orders/{id}/issues","/merchant/orders/{id}/issues","/rider/orders/{id}/issues"})
    public ApiResponse<OrderOperationsService.DeliveryIssue> report(@RequestAttribute("userId") long user,
            @RequestAttribute("role") int role,@PathVariable long id,@RequestBody IssueRequest request,
            jakarta.servlet.http.HttpServletRequest http) {
        requireOrderRoute(role, http.getRequestURI());
        return ApiResponse.ok(operations.report(user,role,id,request.type(),request.note(),request.idempotencyKey()));
    }
    @GetMapping("/admin/delivery-issues")
    public ApiResponse<OrderOperationsService.IssuePage> adminIssues(@RequestAttribute("role") int role,
            @RequestParam(defaultValue="OPEN") String status,@RequestParam(defaultValue="1") int page,@RequestParam(defaultValue="30") int pageSize) {
        requireAdmin(role);return ApiResponse.ok(operations.adminIssues(status,page,pageSize));
    }
    @PostMapping("/admin/delivery-issues/{id}/resolve")
    public ApiResponse<OrderOperationsService.DeliveryIssue> resolve(@RequestAttribute("userId") long user,
            @RequestAttribute("role") int role,@PathVariable long id,@RequestBody ResolveRequest request) {
        requireAdmin(role);return ApiResponse.ok(operations.resolve(user,id,request.action(),request.note()));
    }
    private void requireOrderRoute(int role, String path) {
        int expected = path.contains("/merchant/") ? 1 : path.contains("/rider/") ? 3 : 0;
        if (role != expected) throw new BizException(403, "当前身份不能操作该配送入口");
    }
    private void requireAdmin(int role) { if(role!=2) throw new BizException(403,"仅管理端可处理配送异常"); }
}
