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
 *
 * <p><b>为什么必须钉住</b>：网关是信任边界，两处配置错了都会**静默**造成安全/可用性回归，
 * 且症状离配置很远——表现为「限流莫名其妙不管用」或「所有人一起被限流」，
 * 排查时很难联想到 YAML：</p>
 * <ul>
 *   <li>{@code trusted-proxies} 写成 CIDR（如 {@code 0.0.0.0/0}）而匹配不上直连地址时，
 *       Spring Cloud Gateway 会调用 RemoveXForwardedHeadersFilter 把 X-Forwarded-* **整体剔除**
 *       → 后端退化为用网关地址，全站共用一个限流桶（一个人触发封禁让所有人登录失败，DoS）。</li>
 *   <li>{@code for-append=true} 时，客户端自带的伪造 {@code X-Forwarded-For: 1.2.3.4}
 *       会被保留在列表最前，而后端 {@code clientIp()} 取 {@code split(",")[0]}
 *       → 攻击者每换一个伪造 IP 就重置一个限流桶，**无限绕过登录限流**。</li>
 * </ul>
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

        assertTrue(Boolean.TRUE.equals(enabled), "x-forwarded.enabled 必须为 true，否则客户端 IP 传不到后端");
        assertTrue(Boolean.TRUE.equals(forEnabled), "x-forwarded.for-enabled 必须为 true，限流依赖它");
        // 安全不变量：必须是覆写语义。改成 true 会让客户端伪造的 XFF 排在最前，
        // 而后端 clientIp() 取第一个值 —— 限流可被任意绕过。
        assertFalse(Boolean.TRUE.equals(forAppend),
                "x-forwarded.for-append 必须为 false（覆写）——true 会让客户端伪造 XFF 生效，绕过登录限流");
    }

    @Test
    void trustedProxiesMatchesDirectRemoteAddress() throws Exception {
        Map<String, Object> root = loadGatewayConfig();

        Object trusted = dig(root, "spring", "cloud", "gateway", "server", "webflux", "trusted-proxies");
        assertNotNull(trusted, "trusted-proxies 必须显式配置；不配时网关会剔除 X-Forwarded-*，"
                + "后端只能看到网关地址（全站共用一个限流桶）");

        String pattern = String.valueOf(trusted);
        // 该属性是**正则**，匹配直连网关的远端地址字符串，不是 CIDR 网段。
        // 写成 "0.0.0.0/0" 会因匹配不上 "127.0.0.1" 而静默失效（实测踩过）。
        assertFalse(pattern.contains("0.0.0.0/0"),
                "trusted-proxies 是正则不是 CIDR；写成 0.0.0.0/0 不匹配任何真实地址：pattern=" + pattern);
        assertTrue(pattern.equals(".*") || "127.0.0.1".matches(pattern),
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
    void externalPortContractUnchanged() throws Exception {
        Map<String, Object> root = loadGatewayConfig();

        // 对外契约：网关监听 9000（与拆分前一致），前端 HAP 零改动的前提。
        Object port = dig(root, "server", "port");
        String portValue = String.valueOf(port);
        assertTrue(portValue.contains("9000"), "网关对外端口必须是 9000：实际=" + portValue);
    }
}