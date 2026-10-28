package com.example.takeout.service;

import com.example.takeout.model.MarketingActivity;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class PromotionServiceTest {
    private MarketingActivity activity(long id,String type,double rate,double reduction) {
        return new MarketingActivity(id,10,type,"活动",rate,reduction,0,0,"","",1,"");
    }
    @Test void priceIsIndependentOfActivityOrderAndUsesOnlyBestOffers() {
        var first=activity(1,"DISCOUNT",0.9,0);
        var best=activity(2,"DISCOUNT",0.8,0);
        var small=activity(3,"NEW_USER",0,3);
        var large=activity(4,"NEW_USER",0,5);
        var a=PromotionService.calculate(new BigDecimal("100.00"),List.of(first,best,small,large),true);
        var b=PromotionService.calculate(new BigDecimal("100.00"),List.of(large,best,small,first),true);
        assertEquals(a,b);
        assertEquals(new BigDecimal("80.00"),a.goodsAfterRate());
        assertEquals(new BigDecimal("5.00"),a.newCustomerDiscount());
        assertEquals(new BigDecimal("35.00"),a.discount(new BigDecimal("100.00"),new BigDecimal("10.00")));
        assertEquals(BigDecimal.ZERO,PromotionService.calculate(new BigDecimal("100"),List.of(large),false).newCustomerDiscount());
    }
    @Test void pendingReservationDoesNotGrantAnotherNewCustomerReduction() {
        JdbcTemplate db=mock(JdbcTemplate.class);
        when(db.queryForMap(anyString(),anyLong(),anyLong())).thenReturn(Map.of("state","RESERVED"));
        var quote=new PromotionService(db,new ObjectMapper()).quote(1,10,new BigDecimal("20.00"),List.of(activity(1,"NEW_USER",0,3)));
        assertEquals(BigDecimal.ZERO,quote.newCustomerDiscount());
    }
    @Test void oldCancelledUnpaidOrdersDoNotConsumeFirstPaidOrderEligibility() {
        JdbcTemplate db=mock(JdbcTemplate.class);
        when(db.queryForMap(anyString(),anyLong(),anyLong())).thenReturn(Map.of("state","AVAILABLE"));
        when(db.queryForObject(contains("pay_time<>''"),eq(Integer.class),eq(1L),eq(10L))).thenReturn(0);
        var quote=new PromotionService(db,new ObjectMapper()).quote(1,10,new BigDecimal("20.00"),List.of(activity(1,"NEW_USER",0,3)));
        assertEquals(new BigDecimal("3.00"),quote.newCustomerDiscount());
        verify(db).update(contains("state='RESERVED'"),eq(1L),eq(10L));
    }
}
