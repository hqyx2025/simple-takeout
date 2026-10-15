package com.example.takeout.service.thirdparty;

import org.springframework.web.multipart.MultipartFile;

/**
 * 图片存储：本地开发使用 FileStorageService，生产使用 Huawei OBS。
 */
public interface ObjectStorage {
    /** Return a relative local upload URL or an absolute HTTPS object URL. */
    String store(MultipartFile file);
}
