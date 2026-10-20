package com.example.takeout.controller;

import com.example.takeout.common.BizException;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import java.util.Locale;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;

class LocationControllerTest {
    private final RestClient.Builder builder = RestClient.builder().baseUrl("https://restapi.amap.com");
    private final MockRestServiceServer upstream = MockRestServiceServer.bindTo(builder).build();
    private final LocationController controller = new LocationController("test-key", "", builder.build());

    @Test void convertsBrowserCoordinatesBeforeReverseGeocoding() {
        Locale before = Locale.getDefault();
        try {
            Locale.setDefault(Locale.GERMANY);
            upstream.expect(requestTo(startsWith("https://restapi.amap.com/v3/assistant/coordinate/convert")))
                    .andExpect(queryParam("coordsys", "gps"))
                    .andExpect(queryParam("locations", "116.4000000,39.9000000"))
                    .andRespond(withSuccess("{\"status\":\"1\",\"locations\":\"116.4062,39.9013\"}", MediaType.APPLICATION_JSON));
            upstream.expect(requestTo(startsWith("https://restapi.amap.com/v3/geocode/regeo")))
                    .andExpect(queryParam("location", "116.4062000,39.9013000"))
                    .andRespond(withSuccess("{\"status\":\"1\",\"regeocode\":{\"formatted_address\":\"北京市测试街道\"}}", MediaType.APPLICATION_JSON));
            var result = controller.reverse(116.4, 39.9).data();
            assertEquals(116.4062, result.longitude());
            assertEquals(39.9013, result.latitude());
            assertEquals("北京市测试街道", result.address());
            upstream.verify();
        } finally { Locale.setDefault(before); }
    }

    @Test void rejectsInvalidCoordinatesAndUnavailableMapService() {
        assertThrows(BizException.class, () -> controller.reverse(Double.NaN, 30));
        assertThrows(BizException.class, () -> controller.reverse(181, 30));
        assertThrows(BizException.class, () -> controller.reverse(0, 0));
        upstream.expect(anything()).andRespond(withSuccess("{\"status\":\"0\",\"info\":\"INVALID_USER_KEY\"}", MediaType.APPLICATION_JSON));
        assertThrows(BizException.class, () -> controller.reverse(116.4,39.9));
        upstream.verify();
    }

    @Test void searchPreservesUnicodeAndLiteralQueryCharacters() {
        upstream.expect(requestTo(startsWith("https://restapi.amap.com/v3/place/text")))
                .andExpect(request -> assertEquals("上海{中心}&广场", org.springframework.web.util.UriUtils.decode(
                        org.springframework.web.util.UriComponentsBuilder.fromUri(request.getURI()).build().getQueryParams().getFirst("keywords"), java.nio.charset.StandardCharsets.UTF_8)))
                .andRespond(withSuccess("{\"status\":\"1\",\"pois\":[]}", MediaType.APPLICATION_JSON));
        assertEquals("1", controller.search("上海{中心}&广场").data().path("status").asText());
        upstream.verify();
    }

}
