package com.example.takeout.config;

import com.example.takeout.security.AuthInterceptor;
import com.example.takeout.service.FileStorageService;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web 配置：注册认证拦截器、跨域支持与上传图片的静态资源映射
 * 放行：登录/注册；/uploads/** 为公开静态图片（评价图片展示无需鉴权）
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    private final AuthInterceptor authInterceptor;
    private final ApiRequestLoggingInterceptor apiRequestLoggingInterceptor;
    private final ObjectProvider<FileStorageService> fileStorageService;
    private final com.example.takeout.security.LoginRateLimiter limiter;

    public WebConfig(AuthInterceptor authInterceptor, ApiRequestLoggingInterceptor apiRequestLoggingInterceptor,
                     ObjectProvider<FileStorageService> fileStorageService,
                     com.example.takeout.security.LoginRateLimiter limiter) {
        this.authInterceptor = authInterceptor;
        this.apiRequestLoggingInterceptor = apiRequestLoggingInterceptor;
        this.fileStorageService = fileStorageService;
        this.limiter = limiter;
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        FileStorageService local = fileStorageService.getIfAvailable();
        if (local != null) {
            registry.addResourceHandler("/uploads/**")
                    .addResourceLocations(local.root().toUri().toString());
        }
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(apiRequestLoggingInterceptor)
                .addPathPatterns("/api/**");
        registry.addInterceptor(authInterceptor)
                .addPathPatterns("/api/**")
                .excludePathPatterns(
                        "/api/auth/login",
                        "/api/auth/register",
                        "/api/auth/refresh",
                        "/api/auth/logout",
                        "/api/auth/email-code",
                        "/api/auth/sms-code",
                        "/api/auth/password/forgot",
                        "/api/auth/payment-password/forgot",
                        "/api/payment/wechat/notify",
                        "/api/payment/alipay/notify"
                );
        // 浏览请求在认证之后、查询缓存和数据库之前共用账号预算；写操作不计入。
        registry.addInterceptor(new org.springframework.web.servlet.HandlerInterceptor() {
            @Override public boolean preHandle(jakarta.servlet.http.HttpServletRequest request,
                    jakarta.servlet.http.HttpServletResponse response, Object handler) {
                if (!"GET".equalsIgnoreCase(request.getMethod())) return true;
                Object userId = request.getAttribute("userId");
                if (!(userId instanceof Long)) throw new com.example.takeout.common.BizException(401, "请先登录");
                limiter.recordAttempt("browse", "u" + userId);
                return true;
            }
        }).addPathPatterns("/api/stores/**", "/api/categories", "/api/goods/special", "/api/rankings/**",
                "/api/seckills", "/api/banners", "/api/announcements");
        // 在认证之后、任何地图上游请求之前，所有定位入口共享账号预算。
        registry.addInterceptor(new org.springframework.web.servlet.HandlerInterceptor() {
            @Override public boolean preHandle(jakarta.servlet.http.HttpServletRequest request,
                    jakarta.servlet.http.HttpServletResponse response, Object handler) {
                Object userId = request.getAttribute("userId");
                if (!(userId instanceof Long)) throw new com.example.takeout.common.BizException(401, "请先登录");
                limiter.recordAttempt("location", "u" + userId);
                return true;
            }
        }).addPathPatterns("/api/location/**");
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOrigins("https://hqyx.website")
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .maxAge(3600);
    }
}
