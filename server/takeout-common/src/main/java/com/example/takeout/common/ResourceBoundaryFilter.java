package com.example.takeout.common;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.*;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.LongAdder;

/** Bounds concurrent business work and JSON bodies even when Content-Length is absent. */
@Component
@Order(-100)
public class ResourceBoundaryFilter extends OncePerRequestFilter {
    private final Semaphore permits;
    public final LongAdder rejected=new LongAdder();
    public ResourceBoundaryFilter(@Value("${takeout.admission.max-inflight:48}") int limit) {
        if(limit<1 || limit>512)throw new IllegalArgumentException("Invalid request admission limit");
        permits=new Semaphore(limit);
    }
    @Override protected boolean shouldNotFilter(HttpServletRequest r){return !r.getRequestURI().startsWith("/api/") && !r.getRequestURI().startsWith("/internal/");}
    @Override protected void doFilterInternal(HttpServletRequest r,HttpServletResponse response,FilterChain chain) throws IOException,ServletException {
        if(!permits.tryAcquire()){rejected.increment();fail(response,503,"服务繁忙，请稍后重试");return;}
        try {
            if(r.getContentType()!=null && r.getContentType().toLowerCase(java.util.Locale.ROOT).startsWith("application/json")) {
                // Tomcat's readNBytes(max) allocates max bytes even for a tiny payment body.
                // Stream in bounded chunks so normal JSON requests allocate proportional to their size.
                var content=new ByteArrayOutputStream(1024);
                byte[] chunk=new byte[1024];int count;
                while(content.size()<=262144 && (count=r.getInputStream().read(chunk,0,Math.min(chunk.length,262145-content.size())))!=-1) {
                    content.write(chunk,0,count);
                }
                byte[] bytes=content.toByteArray();
                if(bytes.length>262144){rejected.increment();fail(response,413,"请求内容超过256KiB限制");return;}
                chain.doFilter(new HttpServletRequestWrapper(r){
                    @Override public ServletInputStream getInputStream(){
                        var stream=new ByteArrayInputStream(bytes);
                        return new ServletInputStream(){
                            @Override public int read(){return stream.read();}
                            @Override public int read(byte[] b,int off,int len){return stream.read(b,off,len);}
                            @Override public boolean isFinished(){return stream.available()==0;}
                            @Override public boolean isReady(){return true;}
                            @Override public void setReadListener(ReadListener listener){throw new UnsupportedOperationException();}
                        };
                    }
                    @Override public BufferedReader getReader(){return new BufferedReader(new InputStreamReader(getInputStream(),java.nio.charset.StandardCharsets.UTF_8));}
                },response);
            }else chain.doFilter(r,response);
        }finally{permits.release();}
    }
    private static void fail(HttpServletResponse r,int status,String message)throws IOException{
        r.setStatus(status);r.setHeader("Retry-After","1");r.setContentType("application/json;charset=UTF-8");
        r.getWriter().write("{\"code\":"+status+",\"message\":\""+message+"\",\"data\":null}");
    }
}
