package com.example.takeout.service;

import com.example.takeout.dao.*;
import com.example.takeout.model.Store;
import com.example.takeout.common.BizException;
import org.junit.jupiter.api.Test;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Optional;
import static org.mockito.Mockito.*;
import static org.junit.jupiter.api.Assertions.*;

class EmployeeServiceDefenseTest {
    @Test void owningOneStoreDoesNotAuthorizeDeletionInAnotherStore() {
        StoreDao stores = mock(StoreDao.class);
        EmployeeDao employees = mock(EmployeeDao.class);
        var service = new StoreService(stores, mock(GoodsDao.class), mock(GoodsSpecDao.class), mock(SeckillDao.class),
                new ObjectMapper(), mock(HotDataCacheService.class), employees);
        when(stores.findById(10)).thenReturn(Optional.of(new Store(10, "mine", "", 0, 0, 0, 0,
                "", "", "[]", "", 1, "[1]", 7, 1, 0, "")));
        assertEquals(404, assertThrows(BizException.class, () -> service.removeStoreEmployee(7, 10, 999)).getCode());
        verify(employees).delete(10, 999);
        when(employees.delete(10, 12)).thenReturn(true);
        assertDoesNotThrow(() -> service.removeStoreEmployee(7, 10, 12));
    }
}
