package com.example.takeout.erp;
import com.example.takeout.common.GlobalExceptionHandler;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Import;
@SpringBootApplication
@Import({GlobalExceptionHandler.class,com.example.takeout.common.ResourceBoundaryFilter.class})
public class ErpApplication {
    public static void main(String[] args) { SpringApplication.run(ErpApplication.class, args); }
}
