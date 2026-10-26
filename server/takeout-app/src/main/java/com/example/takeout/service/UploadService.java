package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.security.LoginRateLimiter;
import com.example.takeout.service.thirdparty.ObjectStorage;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

/** 持久化容量预算在本地存储与 OBS 入口共同生效，条件更新支持多实例。 */
@Service
public class UploadService {
    private final JdbcTemplate jdbc;
    private final ObjectStorage storage;
    private final LoginRateLimiter limiter;
    private final long userQuota;
    private final long totalQuota;

    public UploadService(JdbcTemplate jdbc, ObjectStorage storage, LoginRateLimiter limiter,
                         @Value("${takeout.upload.user-quota-bytes:104857600}") long userQuota,
                         @Value("${takeout.upload.total-quota-bytes:21474836480}") long totalQuota) {
        if (userQuota < 1 || totalQuota < userQuota) throw new IllegalStateException("上传容量配置无效");
        this.jdbc = jdbc;
        this.storage = storage;
        this.limiter = limiter;
        this.userQuota = userQuota;
        this.totalQuota = totalQuota;
    }

    @Transactional
    public String store(long userId, MultipartFile file) {
        if (userId <= 0) throw new BizException(401, "请先登录");
        String identity = "u" + userId;
        if (limiter.isBlocked("upload", identity)) throw new BizException(429, "上传过于频繁，请稍后再试");
        limiter.recordAttempt("upload", identity);
        ImageUploadValidator.validate(file);
        // ponytail: 全局预算行串行化上传；吞吐达到瓶颈时改为独立预算预留与补偿。
        // 固定全局→账号的加锁顺序；存储失败时同一事务回滚预算。
        reserve(0, file.getSize(), totalQuota);
        reserve(userId, file.getSize(), userQuota);
        return storage.store(file);
    }

    private void reserve(long userId, long bytes, long quota) {
        // 重复键更新直接取得排他锁，避免 INSERT IGNORE 的共享锁在后续 UPDATE 时升级死锁。
        jdbc.update("INSERT INTO upload_usage(user_id, used_bytes) VALUES(?, 0) "
                + "ON DUPLICATE KEY UPDATE used_bytes = used_bytes", userId);
        if (jdbc.update("UPDATE upload_usage SET used_bytes = used_bytes + ? "
                + "WHERE user_id = ? AND used_bytes <= ?", bytes, userId, quota - bytes) != 1) {
            throw new BizException(429, userId == 0 ? "上传总容量已达上限，请联系管理员" : "账号上传容量已达上限");
        }
    }
}
