package com.example.takeout.job;

import com.example.takeout.service.FinancialReconciliationService;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class FinancialReconciliationJob {
    private final FinancialReconciliationService service;
    public FinancialReconciliationJob(FinancialReconciliationService service) { this.service = service; }
    @Scheduled(fixedDelayString="${takeout.reconciliation.scan-ms:1000}", initialDelay=60000)
    public void scan() { service.scanBatch(); }
}
