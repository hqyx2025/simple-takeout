package com.example.takeout.job;

import com.example.takeout.dao.TokenBlacklistDao;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class TokenCleanupJob {
    private final TokenBlacklistDao tokens;
    public TokenCleanupJob(TokenBlacklistDao tokens) { this.tokens = tokens; }

    @Scheduled(fixedDelay = 60_000, initialDelay = 60_000)
    public void clean() { tokens.deleteExpiredBatch(); }
}
