package com.example.takeout;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * 简单外卖后端服务入口
 * Spring Boot 3.5 + Java 25 + MySQL
 * @EnableScheduling：待付款订单超时自动取消（OrderTimeoutJob）
 */
@SpringBootApplication
@EnableScheduling
@MapperScan("com.example.takeout.mapper")
public class TakeoutApplication {

    public static void main(String[] args) {
        SpringApplication.run(TakeoutApplication.class, args);
    }
}
