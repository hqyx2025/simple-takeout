package com.example.takeout.erp;

import com.example.takeout.common.BizException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class ErpBoundaryTest {
    @Test void malformedIdempotencyKeysAndMissingCommandsNeverReachDatabase()throws Exception {
        var db=mock(JdbcTemplate.class);var tx=mock(TransactionTemplate.class);
        var json=new ObjectMapper();var service=new ErpService(db,tx,json);
        var command=json.readValue("{}",ErpService.Command.class);
        for(String key:new String[]{null,"","short","invalid/request-key-123456","x".repeat(129)})
            assertThrows(BizException.class,()->service.execute(10,99,"supplier-refund",key,command));
        assertThrows(BizException.class,()->service.execute(10,99,"supplier-refund","valid-request-key-123",null));
        verifyNoInteractions(db,tx);
    }
    @Test void unknownResourcesAndUnboundedSearchTermsNeverReachDatabase() {
        var db=mock(JdbcTemplate.class);var tx=mock(TransactionTemplate.class);
        var service=new ErpService(db,tx,new ObjectMapper());
        assertThrows(BizException.class,()->service.list(10,"arbitrary_table",0,50,null,null));
        assertThrows(BizException.class,()->service.list(10,"materials",0,50,null,null,"字".repeat(101),null));
        assertThrows(BizException.class,()->service.list(10,"suppliers",0,50,null,null,"字".repeat(101),true));
        verifyNoInteractions(db,tx);
    }
}
