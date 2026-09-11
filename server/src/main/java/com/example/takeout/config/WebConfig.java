package com.example.takeout.config;

import com.example.takeout.security.AuthInterceptor;
import com.example.takeout.service.FileStorageService;
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
    private final FileStorageService fileStorageService;

    public WebConfig(AuthInterceptor authInterceptor, ApiRequestLoggingInterceptor apiRequestLoggingInterceptor,
                     FileStorageService fileStorageService) {
        this.authInterceptor = authInterceptor;
        this.apiRequestLoggingInterceptor = apiRequestLoggingInterceptor;
        this.fileStorageService = fileStorageService;
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/uploads/**")
                .addResourceLocations(fileStorageService.root().toUri().toString());
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(apiRequestLoggingInterceptor)
                .addPathPatterns("/api/**");
        registry.addInterceptor(authInterceptor)
                .addPathPatterns("/api/**")
                .excludePathPatterns(
                        "/api/auth/login",
                        "/api/auth/register"
                );
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOriginPatterns("*")
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .maxAge(3600);
    }
}
