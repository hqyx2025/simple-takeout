package com.example.takeout.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ProductionHuaweiGuardTest {
    @Test
    void productionDoesNotAcceptMockSmsOrLocalUploadOverrides() {
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("mock", "obs", false, false));
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("qq-email", "local", false, false));
        assertDoesNotThrow(() -> new ProductionHuaweiGuard("qq-email", "obs", false, false));
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("qq-email", "obs", true, false));
        assertThrows(IllegalStateException.class, () -> new ProductionHuaweiGuard("qq-email", "obs", false, true));
    }
}
