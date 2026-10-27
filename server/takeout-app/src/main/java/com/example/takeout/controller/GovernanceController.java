package com.example.takeout.controller;

import com.example.takeout.common.*;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import java.lang.management.*;
import java.util.*;
import javax.sql.DataSource;

@RestController
public class GovernanceController {
    private final JdbcTemplate db;private final String secret;private final DataSource source;
    private final ResourceBoundaryFilter admission;
    public GovernanceController(JdbcTemplate db,DataSource source,ResourceBoundaryFilter admission,
            @Value("${takeout.erp.integration-secret:}") String secret){this.db=db;this.source=source;this.admission=admission;this.secret=secret;}
    @GetMapping("/health")
    public Map<String,Object> health(){db.queryForObject("SELECT 1",Integer.class);return Map.of("status","UP");}
    @GetMapping("/internal/metrics")
    public Map<String,Object> metrics(@RequestHeader(value="X-Integration-Key",required=false) String key){
        IntegrationSecret.require(secret,key);
        var memory=ManagementFactory.getMemoryMXBean();var threads=ManagementFactory.getThreadMXBean();var result=new LinkedHashMap<String,Object>();
        result.put("uptimeMs",ManagementFactory.getRuntimeMXBean().getUptime());
        result.put("heapUsed",memory.getHeapMemoryUsage().getUsed());result.put("heapCommitted",memory.getHeapMemoryUsage().getCommitted());
        result.put("heapMax",memory.getHeapMemoryUsage().getMax());result.put("nonHeapUsed",memory.getNonHeapMemoryUsage().getUsed());
        result.put("threads",threads.getThreadCount());result.put("peakThreads",threads.getPeakThreadCount());
        result.put("gc",ManagementFactory.getGarbageCollectorMXBeans().stream().map(gc->Map.of("name",gc.getName(),"count",gc.getCollectionCount(),"timeMs",gc.getCollectionTime())).toList());
        result.put("buffers",ManagementFactory.getPlatformMXBeans(BufferPoolMXBean.class).stream().map(b->Map.of("name",b.getName(),"used",b.getMemoryUsed(),"count",b.getCount())).toList());
        var os=(com.sun.management.OperatingSystemMXBean)ManagementFactory.getOperatingSystemMXBean();
        result.put("cpuLoad",os.getProcessCpuLoad());result.put("cpuTimeNanos",os.getProcessCpuTime());result.put("availableProcessors",os.getAvailableProcessors());
        result.put("processCommittedVirtualBytes",os.getCommittedVirtualMemorySize());result.put("admissionRejected",admission.rejected.sum());
        if(source instanceof HikariDataSource h && h.getHikariPoolMXBean()!=null){var p=h.getHikariPoolMXBean();result.put("connections",Map.of("active",p.getActiveConnections(),"idle",p.getIdleConnections(),"waiting",p.getThreadsAwaitingConnection(),"total",p.getTotalConnections()));}
        return result;
    }
    @GetMapping("/api/admin/outbox")
    public ApiResponse<?> pending(@RequestAttribute("role") int role){
        admin(role);return ApiResponse.ok(Map.of("summary",db.queryForMap("SELECT COUNT(*) pending,COALESCE(MAX(retry_count),0) maxRetries,MIN(create_time) oldest FROM outbox_events WHERE status=0"),
                "events",db.queryForList("SELECT id,event_type,order_id,retry_count,lease_until,create_time FROM outbox_events WHERE status=0 ORDER BY retry_count DESC,id LIMIT 100")));
    }
    @PostMapping("/api/admin/outbox/{id}/retry")
    @org.springframework.transaction.annotation.Transactional
    public ApiResponse<?> retry(@RequestAttribute("role") int role,@RequestAttribute("userId") long user,@PathVariable long id){
        admin(role);
        // Do not steal an active lease; retry only unowned/backoff or expired deliveries.
        int changed=db.update("UPDATE outbox_events SET lease_until=0,owner='' WHERE id=? AND status=0 AND (owner='' OR lease_until<?)",id,System.currentTimeMillis());
        if(changed==0)throw new BizException(400,"事件已送达、正在投递或不存在");
        db.update("INSERT INTO operation_audit_logs(operator_id,operator_role,action,http_method,request_path,outcome,http_status,created_at) VALUES(?,2,'OUTBOX_RETRY','POST',?,'SUCCESS',200,?)",
                user,"/api/admin/outbox/"+id+"/retry",System.currentTimeMillis());
        return ApiResponse.ok();
    }
    private static void admin(int role){if(role!=2)throw new BizException(403,"仅管理端可补偿事件");}
}
