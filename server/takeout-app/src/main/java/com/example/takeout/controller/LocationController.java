package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;

/** Server-side proxy for Amap Web Service APIs; the REST key never reaches the app. */
@RestController
@RequestMapping("/api/location")
public class LocationController {

    private final RestClient client = RestClient.builder().baseUrl("https://restapi.amap.com").build();
    private final String restKey;
    private final String securityCode;

    public LocationController(@Value("${takeout.amap.rest-key:}") String restKey,
                              @Value("${takeout.amap.security-code:}") String securityCode) {
        this.restKey = restKey == null ? "" : restKey.trim();
        this.securityCode = securityCode == null ? "" : securityCode.trim();
    }

    @GetMapping(value = "/nearby", produces = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> nearby(@RequestParam double longitude, @RequestParam double latitude,
                                        @RequestParam(defaultValue = "1") int page) {
        validateCoordinate(longitude, latitude);
        if (page < 1 || page > 100) throw new BizException("附近地点页码无效");
        return proxy("/v3/place/around", UriComponentsBuilder.newInstance()
                .queryParam("location", "%.6f,%.6f".formatted(longitude, latitude))
                .queryParam("radius", 1000).queryParam("sortrule", "distance")
                .queryParam("offset", 20).queryParam("page", page));
    }

    @GetMapping(value = "/search", produces = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> search(@RequestParam String keyword) {
        String value = keyword == null ? "" : keyword.trim();
        if (value.isEmpty() || value.length() > 80) throw new BizException("搜索关键词无效");
        return proxy("/v3/place/text", UriComponentsBuilder.newInstance()
                .queryParam("keywords", value).queryParam("offset", 20).queryParam("page", 1)
                .queryParam("extensions", "all"));
    }

    @GetMapping(value = "/geocode", produces = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> geocode(@RequestParam String address) {
        String value = address == null ? "" : address.trim();
        if (value.isEmpty() || value.length() > 160) throw new BizException("地址关键词无效");
        return proxy("/v3/geocode/geo", UriComponentsBuilder.newInstance()
                .queryParam("address", value).queryParam("output", "JSON"));
    }

    private ApiResponse<JsonNode> proxy(String path, UriComponentsBuilder builder) {
        if (restKey.isEmpty()) throw new BizException(503, "地图服务未配置，请联系管理员");
        UriComponentsBuilder request = builder.path(path).queryParam("key", restKey);
        if (!securityCode.isEmpty()) {
            request.queryParam("jscode", securityCode);
        }
        JsonNode body = client.get().uri(request.build().toUri())
                .retrieve().body(JsonNode.class);
        if (body == null) throw new BizException(503, "地图服务返回为空");
        return ApiResponse.ok(body);
    }

    private void validateCoordinate(double longitude, double latitude) {
        if (!Double.isFinite(longitude) || !Double.isFinite(latitude)
                || longitude < -180 || longitude > 180 || latitude < -90 || latitude > 90
                || (longitude == 0 && latitude == 0)) {
            throw new BizException("定位坐标无效");
        }
    }
}
