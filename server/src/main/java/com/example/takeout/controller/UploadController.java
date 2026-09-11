package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.service.FileStorageService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 图片上传接口（图文评价）。
 * 返回相对地址 /uploads/yyyyMMdd/xxx.jpg，前端用 API 基址拼接后可直接展示。
 */
@RestController
@RequestMapping("/api")
public class UploadController {

    private final FileStorageService storageService;

    public UploadController(FileStorageService storageService) {
        this.storageService = storageService;
    }

    @PostMapping("/upload")
    public ApiResponse<UploadResult> upload(@RequestParam("file") MultipartFile file) {
        return ApiResponse.ok(new UploadResult(storageService.store(file), file.getSize()));
    }

    /**
     * @param url 相对访问地址（如 /uploads/20260912/ab12.jpg）
     * @param size 文件字节数
     */
    public record UploadResult(String url, long size) {
    }
}
