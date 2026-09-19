package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AnnouncementDao;
import com.example.takeout.dao.BannerDao;
import com.example.takeout.model.Announcement;
import com.example.takeout.model.Banner;
import com.fasterxml.jackson.core.type.TypeReference;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * 内容管理服务：首页轮播 Banner 与平台公告（演进项已落地）。
 * 公开读取接口为首页高频热点，走 Redis 缓存；管理端写操作后立即失效。
 */
@Service
public class ContentService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final BannerDao bannerDao;
    private final AnnouncementDao announcementDao;
    private final HotDataCacheService cache;

    public ContentService(BannerDao bannerDao, AnnouncementDao announcementDao, HotDataCacheService cache) {
        this.bannerDao = bannerDao;
        this.announcementDao = announcementDao;
        this.cache = cache;
    }

    // ===== 公开（需登录） =====

    public List<Banner> publicBanners() {
        return cache.get(HotDataCacheService.Keys.BANNERS,
                new TypeReference<List<Banner>>() {
                },
                bannerDao::listActive);
    }

    public List<Announcement> publicAnnouncements() {
        return cache.get(HotDataCacheService.Keys.ANNOUNCEMENTS,
                new TypeReference<List<Announcement>>() {
                },
                announcementDao::listActive);
    }

    // ===== 管理端 Banner =====

    public List<Banner> adminBanners() {
        return bannerDao.listAll();
    }

    public Banner createBanner(String title, String subtitle, String image, String color,
                               String linkType, String linkValue, int sort) {
        if (title == null || title.isBlank()) {
            throw new BizException("Banner 标题不能为空");
        }
        long id = bannerDao.insert(requireMaxLength(title, 64, "Banner 标题"),
                requireMaxLength(subtitle, 128, "Banner 副标题"),
                requireMaxLength(image, 255, "Banner 图片地址"),
                color == null || color.isBlank() ? "#FF6B35" : color,
                linkType == null || linkType.isBlank() ? "NONE" : linkType,
                requireMaxLength(linkValue, 128, "Banner 跳转参数"), sort,
                LocalDateTime.now().format(FMT));
        cache.evict(HotDataCacheService.Keys.BANNERS);
        return bannerDao.findById(id).orElseThrow(() -> new BizException("Banner 创建失败"));
    }

    public Banner updateBanner(long id, String title, String subtitle, String image, String color,
                               String linkType, String linkValue, int sort) {
        // 旧语义把 null 一律当空串覆盖（非 PATCH），只改 sort 的 PUT 会把 title/subtitle/image 清空；
        // 创建路径本就校验标题非空，更新路径原先没有，这里补齐（列宽同时还可能抛 500）
        if (title == null || title.isBlank()) {
            throw new BizException("Banner 标题不能为空");
        }
        bannerDao.update(id, requireMaxLength(title, 64, "Banner 标题"),
                requireMaxLength(subtitle, 128, "Banner 副标题"),
                requireMaxLength(image, 255, "Banner 图片地址"),
                color == null || color.isBlank() ? "#FF6B35" : color,
                linkType == null || linkType.isBlank() ? "NONE" : linkType,
                requireMaxLength(linkValue, 128, "Banner 跳转参数"), sort);
        cache.evict(HotDataCacheService.Keys.BANNERS);
        return bannerDao.findById(id).orElseThrow(() -> new BizException("Banner 不存在"));
    }

    public void updateBannerStatus(long id, int status) {
        bannerDao.updateStatus(id, status == 1 ? 1 : 0);
        cache.evict(HotDataCacheService.Keys.BANNERS);
    }

    public void deleteBanner(long id) {
        bannerDao.delete(id);
        cache.evict(HotDataCacheService.Keys.BANNERS);
    }

    // ===== 管理端公告 =====

    public List<Announcement> adminAnnouncements() {
        return announcementDao.listAll();
    }

    public Announcement createAnnouncement(String title, String content) {
        if (title == null || title.isBlank()) {
            throw new BizException("公告标题不能为空");
        }
        if (content == null || content.isBlank()) {
            throw new BizException("公告内容不能为空");
        }
        long id = announcementDao.insert(requireMaxLength(title, 128, "公告标题"),
                requireMaxLength(content, 1024, "公告内容"), LocalDateTime.now().format(FMT));
        cache.evict(HotDataCacheService.Keys.ANNOUNCEMENTS);
        return announcementDao.findById(id).orElseThrow(() -> new BizException("公告创建失败"));
    }

    public void updateAnnouncementStatus(long id, int status) {
        announcementDao.updateStatus(id, status == 1 ? 1 : 0);
        cache.evict(HotDataCacheService.Keys.ANNOUNCEMENTS);
    }

    public void deleteAnnouncement(long id) {
        announcementDao.delete(id);
        cache.evict(HotDataCacheService.Keys.ANNOUNCEMENTS);
    }

    /** 列宽上限校验：超长会在写库时抛 500，这里提前给出可读的 400 提示。 */
    private static String requireMaxLength(String value, int maxLength, String field) {
        String safe = value == null ? "" : value.trim();
        if (safe.length() > maxLength) {
            throw new BizException(field + "最多 " + maxLength + " 个字符");
        }
        return safe;
    }
}
