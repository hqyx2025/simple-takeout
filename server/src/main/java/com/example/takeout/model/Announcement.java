package com.example.takeout.model;

/**
 * 平台公告（内容管理，演进项已落地）
 */
public record Announcement(
        long id,
        String title,
        String content,
        int status,
        String createTime
) {
}
