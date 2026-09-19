package com.example.takeout.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * API 网关入口。
 *
 * <p>本模块是 Phase 2 引入的**唯一新增进程**：它把 `:9000` 上原本直连单体的请求
 * 转发给后端应用，从而为后续「按域拆服务」留出路由层。</p>
 *
 * <p><b>为什么现在只路由到一个后端</b>：Phase 2 的目标是「对外契约零变化下先建立路由层」，
 * 拆 catalog/account 是 Phase 3/4 的事。一次性拆完会让回归范围失控，
 * 且违反仓库「一次只做一个可验证的小模块」的既定约束（大纲 §17.2）。</p>
 */
@SpringBootApplication
public class GatewayApplication {

    public static void main(String[] args) {
        SpringApplication.run(GatewayApplication.class, args);
    }
}