package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.service.thirdparty.ObjectStorage;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 图片上传接口（图文评价）。
 * 返回本地相对地址或 OBS/CDN 的 HTTPS 访问地址。
 */
@RestController
@RequestMapping("/api")
public class UploadController {

    private final ObjectStorage storageService;

    public UploadController(ObjectStorage storageService) {
        this.storageService = storageService;
    }

    @PostMapping("/upload")
    public ApiResponse<UploadResult> upload(@RequestParam("file") MultipartFile file) {
        return ApiResponse.ok(new UploadResult(storageService.store(file), file.getSize()));
    }

    /**
     * @param url 本地相对地址或对象存储 HTTPS 访问地址
     * @param size 文件字节数
     */
    public record UploadResult(String url, long size) {
    }
}
