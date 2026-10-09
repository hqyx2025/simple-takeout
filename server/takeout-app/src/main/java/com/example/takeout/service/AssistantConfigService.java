package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.net.InetAddress;
import java.net.URI;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Locale;

/** 管理员维护的单份 AI 配置；API Key 只在服务端解密使用。 */
@Service
public class AssistantConfigService {
    private static final String SELECT = "SELECT enabled, endpoint, model, api_key_encrypted "
            + "FROM assistant_config WHERE id = 1";
    private final JdbcTemplate jdbc;
    private final SecretKeySpec encryptionKey;
    private final SecureRandom random = new SecureRandom();

    public AssistantConfigService(JdbcTemplate jdbc, @Value("${takeout.jwt.secret}") String secret) {
        this.jdbc = jdbc;
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException("AI 配置加密需要服务端密钥");
        }
        try {
            byte[] key = MessageDigest.getInstance("SHA-256").digest(
                    ("takeout:assistant-api-key:v1:" + secret).getBytes(StandardCharsets.UTF_8));
            this.encryptionKey = new SecretKeySpec(key, "AES");
        } catch (GeneralSecurityException ex) {
            throw new IllegalStateException("AI 配置加密不可用");
        }
    }

    public Config load() {
        Stored config = read(false);
        return new Config(config.enabled(), config.endpoint(), config.model(), decrypt(config.encryptedApiKey()));
    }

    public View view() {
        return read(false).view();
    }

    @Transactional
    public View save(SaveRequest request) {
        if (request == null || request.enabled() == null) {
            throw new BizException("请选择是否启用 AI 助手");
        }
        String endpoint = text(request.endpoint(), 1024, "API 地址");
        String model = text(request.model(), 128, "模型名称");
        String apiKey = text(request.apiKey(), 4096, "API Key");
        if (!endpoint.isEmpty()) {
            validateEndpoint(endpoint);
        }
        if (request.clearApiKey() && !apiKey.isEmpty()) {
            throw new BizException("清除密钥时不能同时填写新密钥");
        }
        Stored previous = read(true);
        String encrypted = request.clearApiKey() ? ""
                : apiKey.isEmpty() ? previous.encryptedApiKey() : encrypt(apiKey);
        if (request.enabled() && (endpoint.isEmpty() || model.isEmpty() || encrypted.isEmpty())) {
            throw new BizException("启用 AI 助手前请填写 API 地址、模型名称和 API Key");
        }
        jdbc.update("INSERT INTO assistant_config (id, enabled, endpoint, model, api_key_encrypted) "
                        + "VALUES (1, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE enabled = VALUES(enabled), "
                        + "endpoint = VALUES(endpoint), model = VALUES(model), api_key_encrypted = VALUES(api_key_encrypted)",
                request.enabled() ? 1 : 0, endpoint, model, encrypted);
        return new View(request.enabled(), endpoint, model, !encrypted.isEmpty());
    }

    /** 在保存和发起每次请求前校验，避免配置或 DNS 指向内网服务。 */
    public static URI validateEndpoint(String endpoint) {
        try {
            URI uri = URI.create(endpoint);
            String host = uri.getHost();
            if (!"https".equalsIgnoreCase(uri.getScheme()) || host == null
                    || uri.getRawUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null
                    || (uri.getPort() != -1 && uri.getPort() != 443)
                    || uri.getRawPath() == null || !uri.getRawPath().endsWith("/chat/completions")) {
                throw new BizException("API 地址须为完整的 HTTPS chat/completions 地址，且不能带认证信息、查询参数或片段");
            }
            String lowerHost = host.toLowerCase(Locale.ROOT).replaceAll("\\.$", "");
            if (lowerHost.equals("localhost") || lowerHost.endsWith(".localhost")
                    || lowerHost.endsWith(".local") || lowerHost.endsWith(".internal")
                    || lowerHost.endsWith(".lan") || lowerHost.endsWith(".home")) {
                throw new BizException("API 地址不能指向本机或内网");
            }
            for (InetAddress address : InetAddress.getAllByName(host)) {
                if (!isPublicAddress(address)) {
                    throw new BizException("API 地址不能指向本机、内网或保留网络");
                }
            }
            return uri;
        } catch (BizException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new BizException("API 地址无效或域名无法解析，请检查地址");
        }
    }

    private static boolean isPublicAddress(InetAddress address) {
        if (address.isAnyLocalAddress() || address.isLoopbackAddress() || address.isLinkLocalAddress()
                || address.isSiteLocalAddress() || address.isMulticastAddress()) {
            return false;
        }
        byte[] bytes = address.getAddress();
        int first = bytes[0] & 0xff;
        int second = bytes[1] & 0xff;
        if (bytes.length == 16) {
            // 只接受 IPv6 全球单播；排除文档、Teredo 与 6to4 转换地址。
            return (first & 0xe0) == 0x20
                    && !(first == 0x20 && second == 0x01 && bytes[2] == 0x0d && (bytes[3] & 0xff) == 0xb8)
                    && !(first == 0x20 && second == 0x01 && bytes[2] == 0 && bytes[3] == 0)
                    && !(first == 0x20 && second == 0x02);
        }
        int third = bytes[2] & 0xff;
        return first != 0 && first < 224
                && !(first == 168 && second == 63 && third == 129 && (bytes[3] & 0xff) == 16)
                && !(first == 100 && second >= 64 && second <= 127)
                && !(first == 192 && second == 0 && (third == 0 || third == 2))
                && !(first == 198 && (second == 18 || second == 19))
                && !(first == 198 && second == 51 && third == 100)
                && !(first == 203 && second == 0 && third == 113);
    }

    private Stored read(boolean forUpdate) {
        List<Stored> rows = jdbc.query(SELECT + (forUpdate ? " FOR UPDATE" : ""), (rs, i) -> new Stored(
                rs.getInt("enabled") == 1, rs.getString("endpoint"), rs.getString("model"),
                rs.getString("api_key_encrypted")));
        return rows.isEmpty() ? new Stored(false, "", "", "") : rows.getFirst();
    }

    private String encrypt(String apiKey) {
        try {
            byte[] iv = new byte[12];
            random.nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, encryptionKey, new GCMParameterSpec(128, iv));
            byte[] encrypted = cipher.doFinal(apiKey.getBytes(StandardCharsets.UTF_8));
            return "v1:" + Base64.getEncoder().encodeToString(
                    ByteBuffer.allocate(iv.length + encrypted.length).put(iv).put(encrypted).array());
        } catch (GeneralSecurityException ex) {
            throw new BizException(503, "AI API 密钥保存失败，请稍后重试");
        }
    }

    private String decrypt(String value) {
        if (value.isEmpty()) {
            return "";
        }
        try {
            if (!value.startsWith("v1:")) {
                throw new IllegalArgumentException();
            }
            byte[] bytes = Base64.getDecoder().decode(value.substring(3));
            if (bytes.length < 29) {
                throw new IllegalArgumentException();
            }
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, encryptionKey, new GCMParameterSpec(128, Arrays.copyOf(bytes, 12)));
            return new String(cipher.doFinal(bytes, 12, bytes.length - 12), StandardCharsets.UTF_8);
        } catch (GeneralSecurityException | IllegalArgumentException ex) {
            throw new BizException(503, "AI API 密钥无法读取，请管理员重新保存密钥");
        }
    }

    private static String text(String value, int max, String field) {
        String clean = value == null ? "" : value.trim();
        if (clean.length() > max || clean.chars().anyMatch(Character::isISOControl)) {
            throw new BizException(field + "格式无效或超过长度限制");
        }
        return clean;
    }

    public record Config(boolean enabled, String endpoint, String model, @JsonIgnore String apiKey) {
        @Override
        public String toString() {
            return "Config[enabled=" + enabled + ", endpoint=" + endpoint + ", model=" + model + ", apiKey=[redacted]]";
        }
    }

    public record View(boolean enabled, String endpoint, String model, boolean hasApiKey) { }

    public record SaveRequest(Boolean enabled, String endpoint, String model,
                              @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String apiKey, boolean clearApiKey) {
        @Override
        public String toString() {
            return "SaveRequest[enabled=" + enabled + ", endpoint=" + endpoint + ", model=" + model
                    + ", apiKey=[redacted], clearApiKey=" + clearApiKey + "]";
        }
    }

    private record Stored(boolean enabled, String endpoint, String model, String encryptedApiKey) {
        View view() {
            return new View(enabled, endpoint, model, !encryptedApiKey.isEmpty());
        }
    }
}
