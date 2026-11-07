package com.example.takeout.common;

import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.web.client.RestClient;

/** Preserve the established JsonNode/SDK contract while using Spring 7's native converter configuration. */
public final class JsonRestClients {
    private JsonRestClients() {}

    public static RestClient.Builder builder() {
        return RestClient.builder().configureMessageConverters(converters ->
                converters.withJsonConverter(new MappingJackson2HttpMessageConverter())
                        .configureMessageConvertersList(JsonRestClients::preserveRawStrings));
    }

    public static void preserveRawStrings(java.util.List<org.springframework.http.converter.HttpMessageConverter<?>> converters) {
        converters.removeIf(converter -> converter instanceof org.springframework.http.converter.StringHttpMessageConverter);
        converters.addFirst(new org.springframework.http.converter.StringHttpMessageConverter(java.nio.charset.StandardCharsets.UTF_8));
    }
}
