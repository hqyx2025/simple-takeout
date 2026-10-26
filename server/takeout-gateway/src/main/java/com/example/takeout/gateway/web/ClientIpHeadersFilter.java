package com.example.takeout.gateway.web;

import io.netty.util.NetUtil;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.gateway.filter.headers.HttpHeadersFilter;
import org.springframework.core.Ordered;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import java.util.regex.Pattern;

/** 最后写入单一、已验证来源的 XFF；不依赖 Gateway 的“不可信则删头”分支生成地址。 */
@Component
public class ClientIpHeadersFilter implements HttpHeadersFilter, Ordered {
    private final Pattern trusted;

    public ClientIpHeadersFilter(@Value("${spring.cloud.gateway.server.webflux.trusted-proxies}") String trusted) {
        if (".*".equals(trusted) || ".+".equals(trusted)) throw new IllegalStateException("禁止信任所有代理来源");
        this.trusted = Pattern.compile(trusted);
    }

    @Override public int getOrder() { return Ordered.LOWEST_PRECEDENCE; }

    @Override public HttpHeaders filter(HttpHeaders input, ServerWebExchange exchange) {
        HttpHeaders result = new HttpHeaders();
        result.addAll(input);
        var request = exchange.getRequest();
        var remote = request.getRemoteAddress();
        String peer = remote == null || remote.getAddress() == null ? "unknown" : remote.getAddress().getHostAddress();
        String client = peer;
        String forwarded = request.getHeaders().getFirst("X-Forwarded-For");
        if (trusted.matcher(peer).matches() && forwarded != null) {
            if (forwarded.length() > 2048) throw invalidForwarding();
            String[] hops = forwarded.split(",", -1);
            if (hops.length > 32) throw invalidForwarding();
            {
                for (int i = hops.length - 1; i >= 0; i--) {
                    String hop = hops[i].trim();
                    if (!NetUtil.isValidIpV4Address(hop) && !NetUtil.isValidIpV6Address(hop)) throw invalidForwarding();
                    client = hop;
                    if (!trusted.matcher(hop).matches()) break;
                }
            }
        }
        result.set("X-Forwarded-For", client);
        result.remove("X-Real-IP");
        result.remove("Forwarded");
        return result;
    }

    private ResponseStatusException invalidForwarding() {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid proxy forwarding chain");
    }
}
