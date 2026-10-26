package com.example.takeout.gateway;

import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 网关配置契约测试（直接读 application.yml，不启动 Spring 上下文）。
 * 来源 IP 由 ClientIpHeadersFilter 生成，行为测试另见 ClientIpHeadersFilterTest。
 */
class GatewayXForwardedConfigTest {

    private static Map<String, Object> loadGatewayConfig() throws Exception {
        Path yml = Path.of("src", "main", "resources", "application.yml");
        assertTrue(Files.exists(yml), "网关配置必须存在：" + yml.toAbsolutePath());
        try (InputStream in = Files.newInputStream(yml)) {
            return new Yaml().load(in);
        }
    }

    /** 按路径逐层取嵌套 Map，避免写满 (Map)(Map)(Map) 的强制转换。 */
    @SuppressWarnings("unchecked")
    private static Object dig(Map<String, Object> root, String... path) {
        Object current = root;
        for (String key : path) {
            if (!(current instanceof Map<?, ?> map)) {
                return null;
            }
            current = map.get(key);
        }
        return current;
    }

    @Test
    void xForwardedEnabledAndRewritesClientSuppliedHeader() throws Exception {
        Map<String, Object> root = loadGatewayConfig();

        Object enabled = dig(root, "spring", "cloud", "gateway", "server", "webflux", "x-forwarded", "enabled");
        Object forEnabled = dig(root, "spring", "cloud", "gateway", "server", "webflux", "x-forwarded", "for-enabled");
        Object forAppend = dig(root, "spring", "cloud", "gateway", "server", "webflux", "x-forwarded", "for-append");

        assertTrue(Boolean.TRUE.equals(enabled), "保留 Gateway 的其他转发头处理");
        assertFalse(Boolean.TRUE.equals(forEnabled), "来源地址由 ClientIpHeadersFilter 统一生成");
        assertFalse(Boolean.TRUE.equals(forAppend),
                "不再由 Gateway 内置过滤器追加来源 IP");
    }

    @Test
    void trustedProxiesMatchesDirectRemoteAddress() throws Exception {
        Map<String, Object> root = loadGatewayConfig();

        Object trusted = dig(root, "spring", "cloud", "gateway", "server", "webflux", "trusted-proxies");
        assertNotNull(trusted, "必须明确指定可声明转发来源的受控代理");

        String pattern = new org.springframework.mock.env.MockEnvironment().resolveRequiredPlaceholders(String.valueOf(trusted));
        // 该属性是**正则**，匹配直连网关的远端地址字符串，不是 CIDR 网段。
        // 写成 "0.0.0.0/0" 会因匹配不上 "127.0.0.1" 而静默失效（实测踩过）。
        assertFalse(pattern.contains("0.0.0.0/0"),
                "trusted-proxies 是正则不是 CIDR；写成 0.0.0.0/0 不匹配任何真实地址：pattern=" + pattern);
        assertFalse("192.0.2.10".matches(pattern), "不能信任公网直连来源的转发头");
        assertTrue("127.0.0.1".matches(pattern),
                "trusted-proxies 必须能匹配直连地址（如 127.0.0.1），否则 X-Forwarded-For 会被网关丢弃：pattern=" + pattern);
    }

    @Test
    void routesCoverApiAndUploads() throws Exception {
        Map<String, Object> root = loadGatewayConfig();

        Object routes = dig(root, "spring", "cloud", "gateway", "server", "webflux", "routes");
        assertTrue(routes instanceof List<?>, "必须配置路由列表");

        // 契约不变量：/api/** 与 /uploads/** 都必须被路由——
        // 少了前者前端调不到任何接口，少了后者评价图片全部 404。
        boolean hasApi = false;
        boolean hasUploads = false;
        for (Object route : (List<?>) routes) {
            if (route instanceof Map<?, ?> map) {
                Object predicates = map.get("predicates");
                String joined = String.valueOf(predicates);
                hasApi |= joined.contains("/api/**");
                hasUploads |= joined.contains("/uploads/**");
            }
        }
        assertTrue(hasApi, "必须路由 /api/**（外部契约不变的前提）");
        assertTrue(hasUploads, "必须路由 /uploads/**，否则评价图片 404");
    }

    @Test
    void externalPortUses8087() throws Exception {
        Map<String, Object> root = loadGatewayConfig();

        // 网关入口与前端配置保持一致，应用同机运行时另设 9100。
        Object port = dig(root, "server", "port");
        String portValue = String.valueOf(port);
        assertTrue(portValue.contains("8087"), "网关对外端口必须是 8087：实际=" + portValue);
    }
}
