package com.example.takeout.gateway.web;

import org.springframework.core.annotation.Order;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.server.*;
import reactor.core.publisher.Mono;
import java.nio.charset.StandardCharsets;

/** A failed downstream never silently falls back to another service or retries a write. */
@Component
@Order(-2)
public class GatewayFailureHandler implements WebExceptionHandler {
    @Override public Mono<Void> handle(ServerWebExchange exchange,Throwable error){
        if(exchange.getResponse().isCommitted() || !exchange.getRequest().getPath().value().startsWith("/api/"))return Mono.error(error);
        boolean connection=false,timeout=false;
        for(Throwable cause=error;cause!=null;cause=cause.getCause()){
            connection|=cause instanceof java.net.ConnectException || cause instanceof reactor.netty.http.client.PrematureCloseException;
            timeout|=cause instanceof java.util.concurrent.TimeoutException || cause instanceof io.netty.handler.timeout.ReadTimeoutException;
        }
        if(!connection && !timeout)return Mono.error(error);
        var response=exchange.getResponse();int code=timeout?504:503;
        response.setStatusCode(HttpStatusCode.valueOf(code));response.getHeaders().setContentType(MediaType.APPLICATION_JSON);
        byte[] body=("{\"code\":"+code+",\"message\":\"业务服务暂不可用；写操作结果待确认，请用原请求号核对\",\"data\":null}").getBytes(StandardCharsets.UTF_8);
        return response.writeWith(Mono.just(response.bufferFactory().wrap(body)));
    }
}
