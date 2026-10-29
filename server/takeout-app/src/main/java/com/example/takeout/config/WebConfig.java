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
                        "/api/auth/login/email",
                        "/api/auth/captcha",
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
        // 公开浏览按账号或游客来源共享预算；写操作仍需认证且不计入浏览预算。
        registry.addInterceptor(new org.springframework.web.servlet.HandlerInterceptor() {
            @Override public boolean preHandle(jakarta.servlet.http.HttpServletRequest request,
                    jakarta.servlet.http.HttpServletResponse response, Object handler) {
                if (!"GET".equalsIgnoreCase(request.getMethod())) return true;
                Object userId = request.getAttribute("userId");
                String identity = userId instanceof Long ? "u" + userId
                        : "ip:" + com.example.takeout.security.LoginRateLimiter.clientIp(request);
                limiter.recordAttempt("browse", identity);
                return true;
            }
        }).addPathPatterns(AuthInterceptor.PUBLIC_BROWSE_PATHS.toArray(String[]::new));
        // 地点查询也是公开读取；所有定位入口按账号或游客来源共享预算。
        registry.addInterceptor(new org.springframework.web.servlet.HandlerInterceptor() {
            @Override public boolean preHandle(jakarta.servlet.http.HttpServletRequest request,
                    jakarta.servlet.http.HttpServletResponse response, Object handler) {
                Object userId = request.getAttribute("userId");
                String identity = userId instanceof Long ? "u" + userId
                        : "ip:" + com.example.takeout.security.LoginRateLimiter.clientIp(request);
                limiter.recordAttempt("location", identity);
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
