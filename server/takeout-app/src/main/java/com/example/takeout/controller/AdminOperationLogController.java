package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.dao.OperationAuditLogDao;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/admin")
public class AdminOperationLogController {

    private final OperationAuditLogDao operationLogDao;

    public AdminOperationLogController(OperationAuditLogDao operationLogDao) {
        this.operationLogDao = operationLogDao;
    }

    @GetMapping("/audit-logs")
    public ApiResponse<OperationLogPage> list(@RequestAttribute("role") int role,
                                              @RequestParam(defaultValue = "1") int page,
                                              @RequestParam(defaultValue = "50") int pageSize) {
        if (role != 2) {
            throw new BizException(403, "仅管理端可以查看操作审计");
        }
        int currentPage = Math.max(page, 1);
        int size = Math.clamp(pageSize, 1, 100);
        int total = operationLogDao.count();
        long offset = (long) (currentPage - 1) * size;
        List<OperationAuditLogDao.OperationLog> list = operationLogDao.list(size, offset);
        return ApiResponse.ok(new OperationLogPage(list, total, currentPage, size, (long) currentPage * size < total));
    }

    public record OperationLogPage(List<OperationAuditLogDao.OperationLog> list, int total,
                                   int page, int pageSize, boolean hasMore) {
    }
}
