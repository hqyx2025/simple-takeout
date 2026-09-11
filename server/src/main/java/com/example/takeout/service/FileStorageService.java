package com.example.takeout.service;

import com.example.takeout.common.BizException;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

/**
 * 本地图片存储（图文评价上传）。
 * 图片存放在 takeout.upload.dir（默认工作目录下的 uploads），按天分目录，
 * 对外通过 WebConfig 注册的 /uploads/** 静态资源访问。
 * 说明：毕设环境不引入 OSS，故采用本地文件存储；生产环境可替换为对象存储实现。
 */
@Service
public class FileStorageService {

    /** 允许的图片扩展名。 */
    private static final Set<String> ALLOWED_EXTENSIONS = Set.of("jpg", "jpeg", "png", "webp", "gif");

    /** 单张图片大小上限 5MB。 */
    private static final long MAX_BYTES = 5L * 1024 * 1024;

    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final Path root;

    public FileStorageService(@Value("${takeout.upload.dir:uploads}") String uploadDir) {
        this.root = Paths.get(uploadDir).toAbsolutePath().normalize();
    }

    @PostConstruct
    void init() throws IOException {
        Files.createDirectories(root);
    }

    /** 静态资源映射目录（WebConfig 使用）。 */
    public Path root() {
        return root;
    }

    /**
     * 保存上传图片，返回可直接拼接访问的相对地址（/uploads/yyyyMMdd/xxx.jpg）。
     */
    public String store(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BizException("请选择要上传的图片");
        }
        if (file.getSize() > MAX_BYTES) {
            throw new BizException("图片大小不能超过 5MB");
        }
        String originalName = file.getOriginalFilename() == null ? "" : file.getOriginalFilename();
        String extension = extensionOf(originalName);
        if (!ALLOWED_EXTENSIONS.contains(extension)) {
            throw new BizException("仅支持 jpg / png / webp / gif 格式的图片");
        }
        String contentType = file.getContentType();
        if (contentType != null && !contentType.toLowerCase(Locale.ROOT).startsWith("image/")) {
            throw new BizException("仅支持上传图片文件");
        }
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

    private String extensionOf(String fileName) {
        int index = fileName.lastIndexOf('.');
        if (index < 0 || index == fileName.length() - 1) {
            return "";
        }
        return fileName.substring(index + 1).toLowerCase(Locale.ROOT);
    }
}
