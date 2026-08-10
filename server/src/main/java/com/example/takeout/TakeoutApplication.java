package com.example.takeout;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.nio.file.Files;
import java.nio.file.Path;

/**
 * 简单外卖后端服务入口
 * Spring Boot 3.5 + Java 25 + SQLite
 */
@SpringBootApplication
public class TakeoutApplication {

    static {
        // SQLite 不会自动创建父目录，须在数据源初始化前确保 data 目录存在
        try {
            Files.createDirectories(Path.of("data"));
        } catch (Exception ignored) {
            // 目录已存在或创建失败时忽略（后续连接时会再次报错）
        }
    }

    public static void main(String[] args) {
        SpringApplication.run(TakeoutApplication.class, args);
    }
}
