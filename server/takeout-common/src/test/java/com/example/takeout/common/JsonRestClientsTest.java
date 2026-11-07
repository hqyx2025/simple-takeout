package com.example.takeout.common;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;

class JsonRestClientsTest {
    public record Payload(String value, @JsonIgnore String secret) {}

    @Test void preservesRawJsonStringsAndReadsTheExistingJsonNodeType() {
        var builder=JsonRestClients.builder().baseUrl("https://provider.test");
        var server=MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo("https://provider.test/data"))
                .andExpect(content().string("{\"amount\":123.45}"))
                .andRespond(withSuccess("{\"amount\":123.45,\"code\":200}",MediaType.APPLICATION_JSON));
        JsonNode result=builder.build().post().uri("/data").contentType(MediaType.APPLICATION_JSON)
                .body("{\"amount\":123.45}").retrieve().body(JsonNode.class);
        assertNotNull(result);assertEquals(200,result.path("code").asInt());
        assertEquals(new java.math.BigDecimal("123.45"),result.path("amount").decimalValue());server.verify();
    }

    @Test void existingIgnoredSecretsAreOmittedFromTypedJsonPayloads() {
        var builder=JsonRestClients.builder().baseUrl("https://provider.test");
        var server=MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo("https://provider.test/data"))
                .andExpect(content().string("{\"value\":\"ok\"}"))
                .andRespond(withSuccess("{}",MediaType.APPLICATION_JSON));
        builder.build().post().uri("/data").body(new Payload("ok","must-never-be-sent")).retrieve().toBodilessEntity();server.verify();
    }
}
