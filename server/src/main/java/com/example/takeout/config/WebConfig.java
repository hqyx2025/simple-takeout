package com.example.takeout.config;

import com.example.takeout.security.AuthInterceptor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web 配置：注册认证拦截器与跨域支持
 * 放行：登录/注册、店铺与商品浏览（游客可看）、分类
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    private final AuthInterceptor authInterceptor;
    private final ApiRequestLoggingInterceptor apiRequestLoggingInterceptor;

    public WebConfig(AuthInterceptor authInterceptor, ApiRequestLoggingInterceptor apiRequestLoggingInterceptor) {
        this.authInterceptor = authInterceptor;
        this.apiRequestLoggingInterceptor = apiRequestLoggingInterceptor;
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
