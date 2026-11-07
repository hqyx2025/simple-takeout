package com.example.takeout.config;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;

class MigrationReadinessFilterTest {
    @Test void doesNotAcceptLoginsOrHealthyProbesBeforeAllMigrationsHaveCompleted() throws Exception {
        var filter=new MigrationReadinessFilter(); var calls=new AtomicInteger();
        for(String path:new String[]{"/api/auth/login","/api/orders","/health"}) {
            var response=new MockHttpServletResponse();
            filter.doFilter(new MockHttpServletRequest("GET",path),response,(req,res)->calls.incrementAndGet());
            assertEquals(503,response.getStatus()); assertEquals("2",response.getHeader("Retry-After"));
        }
        assertEquals(0,calls.get()); filter.applicationReady();
        var response=new MockHttpServletResponse();
        filter.doFilter(new MockHttpServletRequest("GET","/api/orders"),response,(req,res)->calls.incrementAndGet());
        assertEquals(1,calls.get()); assertEquals(200,response.getStatus());
    }
}
