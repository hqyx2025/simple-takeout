package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.model.Announcement;
import com.example.takeout.model.Banner;
import com.example.takeout.service.ContentService;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 管理端内容管理（Banner / 公告）。要求 role=2（ADMIN）。
 */
@RestController
@RequestMapping("/api/admin")
public class AdminContentController {

    private final ContentService contentService;

    public AdminContentController(ContentService contentService) {
        this.contentService = contentService;
    }

    // ===== Banner =====

    @GetMapping("/banners")
    public ApiResponse<List<Banner>> banners(@RequestAttribute("role") int role) {
        requireAdmin(role);
        return ApiResponse.ok(contentService.adminBanners());
    }

    @PostMapping("/banners")
    public ApiResponse<Banner> createBanner(@RequestAttribute("role") int role,
                                            @RequestBody BannerRequest req) {
        requireAdmin(role);
        return ApiResponse.ok(contentService.createBanner(req.title(), req.subtitle(), req.image(),
                req.color(), req.linkType(), req.linkValue(), req.sort()));
    }

    @PutMapping("/banners/{id}")
    public ApiResponse<Banner> updateBanner(@RequestAttribute("role") int role,
                                            @PathVariable long id,
                                            @RequestBody BannerRequest req) {
        requireAdmin(role);
        return ApiResponse.ok(contentService.updateBanner(id, req.title(), req.subtitle(), req.image(),
                req.color(), req.linkType(), req.linkValue(), req.sort()));
    }

    @PutMapping("/banners/{id}/status")
    public ApiResponse<Void> updateBannerStatus(@RequestAttribute("role") int role,
                                                @PathVariable long id,
                                                @RequestBody StatusRequest req) {
        requireAdmin(role);
        contentService.updateBannerStatus(id, req.status());
        return ApiResponse.ok();
    }

    @DeleteMapping("/banners/{id}")
    public ApiResponse<Void> deleteBanner(@RequestAttribute("role") int role, @PathVariable long id) {
        requireAdmin(role);
        contentService.deleteBanner(id);
        return ApiResponse.ok();
    }

    // ===== 公告 =====

    @GetMapping("/announcements")
    public ApiResponse<List<Announcement>> announcements(@RequestAttribute("role") int role) {
        requireAdmin(role);
        return ApiResponse.ok(contentService.adminAnnouncements());
    }

    @PostMapping("/announcements")
    public ApiResponse<Announcement> createAnnouncement(@RequestAttribute("role") int role,
                                                        @RequestBody AnnouncementRequest req) {
        requireAdmin(role);
        return ApiResponse.ok(contentService.createAnnouncement(req.title(), req.content()));
    }

    @PutMapping("/announcements/{id}/status")
    public ApiResponse<Void> updateAnnouncementStatus(@RequestAttribute("role") int role,
                                                      @PathVariable long id,
                                                      @RequestBody StatusRequest req) {
        requireAdmin(role);
        contentService.updateAnnouncementStatus(id, req.status());
        return ApiResponse.ok();
    }

    @DeleteMapping("/announcements/{id}")
    public ApiResponse<Void> deleteAnnouncement(@RequestAttribute("role") int role, @PathVariable long id) {
        requireAdmin(role);
        contentService.deleteAnnouncement(id);
        return ApiResponse.ok();
    }

    public record BannerRequest(String title, String subtitle, String image, String color,
                                String linkType, String linkValue, int sort) {
    }

    public record AnnouncementRequest(String title, String content) {
    }

    public record StatusRequest(int status) {
    }

    private void requireAdmin(int role) {
        if (role != 2) {
            throw new BizException(403, "仅平台管理员可以执行该操作");
        }
    }
}
