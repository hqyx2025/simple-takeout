package com.example.takeout.service.thirdparty;

import org.springframework.web.multipart.MultipartFile;

/**
 * 对象存储适配（OSS 接口化）：默认本地文件实现（FileStorageService），
 * 生产环境可替换为阿里云 OSS / 腾讯云 COS 等实现，UploadController 只依赖本接口。
 */
public interface ObjectStorage {
    /** 保存上传文件，返回可直接访问的相对地址（如 /uploads/yyyyMMdd/xxx.jpg）。 */
    String store(MultipartFile file);
}
