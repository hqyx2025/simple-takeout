package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.service.thirdparty.ObjectStorage;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.UUID;

/**
 * 本地图片存储（图文评价上传）。
 * 图片存放在 takeout.upload.dir（默认工作目录下的 uploads），按天分目录，
 * 对外通过 WebConfig 注册的 /uploads/** 静态资源访问。
 * 仅用于本地开发；生产环境使用 Huawei OBS 实现。
 */
@Service
@ConditionalOnProperty(name = "takeout.upload.provider", havingValue = "local", matchIfMissing = true)
public class FileStorageService implements ObjectStorage {

    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final Path root;

    @Value("${takeout.upload.local-enabled:true}")
    private boolean localStorageEnabled = true;

    public FileStorageService(@Value("${takeout.upload.dir:uploads}") String uploadDir) {
        this.root = Paths.get(uploadDir).toAbsolutePath().normalize();
    }

    @PostConstruct
    void init() throws IOException {
        if (localStorageEnabled) {
            Files.createDirectories(root);
        }
    }

    /** 静态资源映射目录（WebConfig 使用）。 */
    public Path root() {
        return root;
    }

    /**
     * 保存上传图片，返回可直接拼接访问的相对地址（/uploads/yyyyMMdd/xxx.jpg）。
     */
    @Override
    public String store(MultipartFile file) {
        if (!localStorageEnabled) {
            throw new BizException("本地文件上传已关闭，请配置对象存储服务");
        }
        String extension = ImageUploadValidator.validate(file);
        String day = LocalDate.now().format(DAY);
        String fileName = UUID.randomUUID().toString().replace("-", "") + "." + extension;
        try {
            Path targetDir = root.resolve(day).normalize();
            if (!targetDir.startsWith(root)) {
                throw new BizException("非法的上传路径");
            }
            Files.createDirectories(targetDir);
            Path target = targetDir.resolve(fileName);
            try (var in = file.getInputStream()) {
                Files.copy(in, target, StandardCopyOption.REPLACE_EXISTING);
            }
            return "/uploads/" + day + "/" + fileName;
        } catch (IOException e) {
            throw new BizException("图片保存失败，请稍后重试");
        }
    }

}
