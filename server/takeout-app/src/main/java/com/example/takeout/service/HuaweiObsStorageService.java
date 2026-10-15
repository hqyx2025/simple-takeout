package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.service.thirdparty.ObjectStorage;
import com.obs.services.ObsClient;
import com.obs.services.ObsConfiguration;
import com.obs.services.model.ObjectMetadata;
import jakarta.annotation.PreDestroy;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.net.URI;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.UUID;

@Service
@ConditionalOnProperty(name = "takeout.upload.provider", havingValue = "obs")
public class HuaweiObsStorageService implements ObjectStorage {

    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final ObsClient client;
    private final String bucket;
    private final String publicBaseUrl;

    public HuaweiObsStorageService(
            @Value("${takeout.upload.huawei.endpoint:}") String endpoint,
            @Value("${takeout.upload.huawei.bucket:}") String bucket,
            @Value("${takeout.upload.huawei.access-key:}") String accessKey,
            @Value("${takeout.upload.huawei.secret-key:}") String secretKey,
            @Value("${takeout.upload.huawei.public-base-url:}") String publicBaseUrl) {
        if (blank(bucket) || blank(accessKey) || blank(secretKey) || !httpsUrl(endpoint) || !httpsUrl(publicBaseUrl)) {
            throw new IllegalStateException("Huawei OBS configuration is incomplete or invalid");
        }
        this.bucket = bucket;
        this.publicBaseUrl = publicBaseUrl.replaceAll("/$", "");
        ObsConfiguration configuration = new ObsConfiguration();
        configuration.setEndPoint(endpoint);
        this.client = new ObsClient(accessKey, secretKey, configuration);
    }

    @Override
    public String store(MultipartFile file) {
        String extension = ImageUploadValidator.validate(file);
        String key = "uploads/" + LocalDate.now().format(DAY) + "/"
                + UUID.randomUUID().toString().replace("-", "") + "." + extension;
        ObjectMetadata metadata = new ObjectMetadata();
        metadata.setContentLength(file.getSize());
        metadata.setContentType(file.getContentType());
        try (var input = file.getInputStream()) {
            client.putObject(bucket, key, input, metadata);
            return publicBaseUrl + "/" + key;
        } catch (IOException | RuntimeException e) {
            throw new BizException("图片上传失败，请稍后重试");
        }
    }

    @PreDestroy
    public void close() throws Exception {
        client.close();
    }

    private static boolean httpsUrl(String value) {
        if (blank(value)) return false;
        try {
            URI uri = URI.create(value);
            return "https".equalsIgnoreCase(uri.getScheme()) && uri.getHost() != null;
        } catch (IllegalArgumentException e) {
            return false;
        }
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }
}
