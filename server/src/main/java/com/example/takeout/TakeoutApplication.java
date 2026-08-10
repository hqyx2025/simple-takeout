package com.example.takeout;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 简单外卖后端服务入口
 * Spring Boot 3.5 + Java 25 + MySQL
 */
@SpringBootApplication
public class TakeoutApplication {

    public static void main(String[] args) {
        SpringApplication.run(TakeoutApplication.class, args);
    }
}
