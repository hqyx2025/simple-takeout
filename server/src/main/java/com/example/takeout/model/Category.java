package com.example.takeout.model;

/**
 * 店铺分类
 */
public record Category(
        long id,
        String name,
        String icon,
        String color
) {
}
