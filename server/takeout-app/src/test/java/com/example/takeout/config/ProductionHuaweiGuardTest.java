package com.example.takeout.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ProductionHuaweiGuardTest {
    @Test
    void productionDoesNotAcceptMockSmsOrLocalUploadOverrides() {
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("mock", "obs", false, false));
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("huawei", "local", false, false));
        assertDoesNotThrow(() -> new ProductionHuaweiGuard("huawei", "obs", false, false));
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("huawei", "obs", true, false));
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("huawei", "obs", false, true));
    }
}
