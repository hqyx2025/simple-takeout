package com.example.takeout.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class OpenApiConfigTest {

    @Test
    void declaresConfiguredServerAndBearerJwtScheme() {
        var api = new OpenApiConfig().takeoutOpenApi("https://api.example.test");

        assertEquals("https://api.example.test", api.getServers().getFirst().getUrl());
        assertNotNull(api.getComponents().getSecuritySchemes().get("bearerAuth"));
        assertEquals("bearer", api.getComponents().getSecuritySchemes().get("bearerAuth").getScheme());
    }
}
