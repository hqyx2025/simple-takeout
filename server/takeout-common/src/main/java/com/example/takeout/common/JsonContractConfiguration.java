package com.example.takeout.common;

import org.springframework.boot.http.converter.autoconfigure.ServerHttpMessageConvertersCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Payment callback signatures cover the original JSON bytes, never a JSON-encoded String. */
@Configuration(proxyBeanMethods=false)
public class JsonContractConfiguration {
    @Bean
    ServerHttpMessageConvertersCustomizer preserveSignedRawBodies() {
        return converters -> converters.configureMessageConvertersList(JsonRestClients::preserveRawStrings);
    }
}
