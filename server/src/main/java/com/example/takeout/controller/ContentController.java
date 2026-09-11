package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.model.Announcement;
import com.example.takeout.model.Banner;
import com.example.takeout.service.ContentService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 内容公开接口：首页轮播 Banner 与平台公告（均需登录，与全量拦截口径一致）。
 */
@RestController
@RequestMapping("/api")
public class ContentController {

    private final ContentService contentService;

    public ContentController(ContentService contentService) {
        this.contentService = contentService;
    }

    @GetMapping("/banners")
    public ApiResponse<List<Banner>> banners() {
        return ApiResponse.ok(contentService.publicBanners());
    }

    @GetMapping("/announcements")
    public ApiResponse<List<Announcement>> announcements() {
        return ApiResponse.ok(contentService.publicAnnouncements());
    }
}
