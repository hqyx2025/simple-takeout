package com.example.takeout.erp;

import com.example.takeout.common.BizException;
import com.example.takeout.common.CrudOperation;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestClient;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;

class ErpPermissionTest {
    @Test void everyWriteChecksItsActualOperationAtTheAuthorityBeforeMutating() {
        for(String action:new String[]{"suppliers","materials","purchases","receive","adjust","pay",
                "supplier-update","supplier-status","submit","confirm","close","review","reverse",
                "reverse-receipt","payment-correct","reverse-payment","supplier-refund"}) {
            var service=mock(ErpService.class);
            var db=mock(JdbcTemplate.class);
            var builder=com.example.takeout.common.JsonRestClients.builder().baseUrl("http://authority.test");
            var server=MockRestServiceServer.bindTo(builder).build();
            var controller=new ErpController(service,db,"http://authority.test","test-integration-secret-32-characters");
            ReflectionTestUtils.setField(controller,"app",builder.build());
            String operation=ErpController.operationFor(action).name();
            server.expect(requestTo("http://authority.test/api/internal/erp/context?storeId=10&operation="+operation))
                    .andRespond(withStatus(HttpStatus.FORBIDDEN));
            assertEquals(403,assertThrows(BizException.class,()->controller.write(10,action,"Bearer token","test-request-key-123",null)).getCode());
            server.verify();
            verifyNoInteractions(service,db);
        }
    }

    @Test void createOnlyAccountCanWriteWithoutRequiringReadPermission() {
        var service=mock(ErpService.class);
        var db=mock(JdbcTemplate.class);
        var builder=com.example.takeout.common.JsonRestClients.builder().baseUrl("http://authority.test");
        var server=MockRestServiceServer.bindTo(builder).build();
        var controller=new ErpController(service,db,"http://authority.test","test-integration-secret-32-characters");
        ReflectionTestUtils.setField(controller,"app",builder.build());
        server.expect(requestTo("http://authority.test/api/internal/erp/context?storeId=10&operation=CREATE"))
                .andRespond(withSuccess("{\"code\":200,\"data\":{\"userId\":99}}",MediaType.APPLICATION_JSON));
        when(service.execute(10,99,"purchases","test-request-key-123",null)).thenReturn(Map.of("id",7));
        assertEquals(Map.of("id",7),controller.write(10,"purchases","Bearer token","test-request-key-123",null).data());
        server.verify();
        assertEquals(CrudOperation.UPDATE,ErpController.operationFor("reverse-receipt"));
        assertThrows(BizException.class,()->ErpController.operationFor("unknown"));
    }
}
