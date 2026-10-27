package com.example.takeout.gateway.web;

import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.Resource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** 公网体验页：与 API 网关共用 8087 入口，免去额外的前端运行时。 */
@RestController
public class WebHomeController {

    @GetMapping("/health")
    public java.util.Map<String,String> health(){return java.util.Map.of("status","UP","service","takeout-gateway");}

    private final Resource index = new ClassPathResource("static/index.html");

    @GetMapping(value = {"/", "/index.html"}, produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<Resource> index() {
        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(index);
    }
}
