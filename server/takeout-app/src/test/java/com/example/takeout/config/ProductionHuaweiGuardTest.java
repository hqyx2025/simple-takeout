package com.example.takeout.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ProductionHuaweiGuardTest {
    @Test
    void productionDoesNotAcceptMockSmsOrLocalUploadOverrides() {
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("mock", "obs"));
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("huawei", "local"));
        assertDoesNotThrow(() -> new ProductionHuaweiGuard("huawei", "obs"));
    }
}
