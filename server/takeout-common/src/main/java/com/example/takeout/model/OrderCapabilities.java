package com.example.takeout.model;

import java.util.List;

/** Server-owned actions and monetary limits, independent of client status labels. */
public record OrderCapabilities(List<String> allowedActions, double refundRemaining, String afterSalesDeadline,
                                String fulfillmentMode) {
    public OrderCapabilities { allowedActions = List.copyOf(allowedActions); }
}
