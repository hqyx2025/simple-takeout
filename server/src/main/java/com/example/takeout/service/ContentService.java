package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AnnouncementDao;
import com.example.takeout.dao.BannerDao;
import com.example.takeout.model.Announcement;
import com.example.takeout.model.Banner;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * 内容管理服务：首页轮播 Banner 与平台公告（演进项已落地）。
 */
@Service
public class ContentService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final BannerDao bannerDao;
    private final AnnouncementDao announcementDao;

    public ContentService(BannerDao bannerDao, AnnouncementDao announcementDao) {
        this.bannerDao = bannerDao;
        this.announcementDao = announcementDao;
    }

    // ===== 公开（需登录） =====

    public List<Banner> publicBanners() {
        return bannerDao.listActive();
    }

    public List<Announcement> publicAnnouncements() {
        return announcementDao.listActive();
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
        long id = bannerDao.insert(title.trim(), subtitle == null ? "" : subtitle, image == null ? "" : image,
                color == null || color.isBlank() ? "#FF6B35" : color,
                linkType == null || linkType.isBlank() ? "NONE" : linkType,
                linkValue == null ? "" : linkValue, sort, LocalDateTime.now().format(FMT));
        return bannerDao.findById(id).orElseThrow(() -> new BizException("Banner 创建失败"));
    }

    public Banner updateBanner(long id, String title, String subtitle, String image, String color,
                               String linkType, String linkValue, int sort) {
        bannerDao.update(id, title == null ? "" : title.trim(), subtitle == null ? "" : subtitle,
                image == null ? "" : image, color == null || color.isBlank() ? "#FF6B35" : color,
                linkType == null || linkType.isBlank() ? "NONE" : linkType, linkValue == null ? "" : linkValue, sort);
        return bannerDao.findById(id).orElseThrow(() -> new BizException("Banner 不存在"));
    }

    public void updateBannerStatus(long id, int status) {
        bannerDao.updateStatus(id, status == 1 ? 1 : 0);
    }

    public void deleteBanner(long id) {
        bannerDao.delete(id);
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
        long id = announcementDao.insert(title.trim(), content.trim(), LocalDateTime.now().format(FMT));
        return announcementDao.findById(id).orElseThrow(() -> new BizException("公告创建失败"));
    }

    public void updateAnnouncementStatus(long id, int status) {
        announcementDao.updateStatus(id, status == 1 ? 1 : 0);
    }

    public void deleteAnnouncement(long id) {
        announcementDao.delete(id);
    }
}
