package com.example.takeout.common;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

class ResourceBoundaryFilterTest {
    private MockHttpServletRequest request(int size,boolean chunked){
        var r=new MockHttpServletRequest(){@Override public long getContentLengthLong(){return chunked?-1:super.getContentLengthLong();}};
        r.setRequestURI("/api/orders");r.setContentType("application/json");r.setContent(new byte[size]);return r;
    }
    @Test void boundsBothKnownAndChunkedJsonBeforeController()throws Exception{
        var filter=new ResourceBoundaryFilter(1);
        for(boolean chunked:new boolean[]{false,true}){
            var response=new MockHttpServletResponse();
            filter.doFilter(request(262145,chunked),response,(r,s)->fail("oversize body reached controller"));
            assertEquals(413,response.getStatus());
        }
        var response=new MockHttpServletResponse();
        filter.doFilter(request(262144,true),response,(r,s)->assertEquals(262144,r.getInputStream().readAllBytes().length));
        assertEquals(200,response.getStatus());
    }
    @Test void saturatedRequestsRejectAndCapacityRecovers()throws Exception{
        var filter=new ResourceBoundaryFilter(1);var entered=new CountDownLatch(1);var release=new CountDownLatch(1);
        try(var pool=Executors.newSingleThreadExecutor()){
            var first=pool.submit(()->{try{filter.doFilter(request(20,false),new MockHttpServletResponse(),(r,s)->{
                entered.countDown();try{assertTrue(release.await(3,TimeUnit.SECONDS));}catch(InterruptedException e){throw new IllegalStateException(e);}
            });}catch(Exception e){throw new IllegalStateException(e);}});
            assertTrue(entered.await(2,TimeUnit.SECONDS));var second=new MockHttpServletResponse();
            try{filter.doFilter(request(20,true),second,(r,s)->fail("saturated request admitted"));assertEquals(503,second.getStatus());}
            finally{release.countDown();}
            first.get(3,TimeUnit.SECONDS);
            var third=new MockHttpServletResponse();filter.doFilter(request(20,true),third,(r,s)->assertEquals(20,r.getInputStream().readAllBytes().length));
            assertEquals(200,third.getStatus());assertEquals(1,filter.rejected.sum());
        }
    }
    @Test void controllerFailureDoesNotLeakPermit()throws Exception{
        var filter=new ResourceBoundaryFilter(1);
        assertThrows(jakarta.servlet.ServletException.class,()->filter.doFilter(request(8,false),new MockHttpServletResponse(),(r,s)->{throw new jakarta.servlet.ServletException();}));
        var response=new MockHttpServletResponse();filter.doFilter(request(8,false),response,(r,s)->assertEquals(8,r.getInputStream().readAllBytes().length));assertEquals(200,response.getStatus());
    }
}
