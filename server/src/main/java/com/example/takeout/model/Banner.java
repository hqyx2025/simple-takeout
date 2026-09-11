package com.example.takeout.model;

/**
 * 首页轮播 Banner（内容管理，演进项已落地）
 */
public record Banner(
        long id,
        String title,
        String subtitle,
        String image,
        String color,
        String linkType,
        String linkValue,
        int sort,
        int status,
        String createTime
) {
}
