package com.example.takeout.service;

import java.sql.SQLException;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Consumer;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

/** Only retry database-deadlocked short transactions; never wrap provider/network orchestration. */
public final class TransactionRetries {
    private TransactionRetries() {}

    public static <T> T execute(TransactionTemplate transactions, TransactionCallback<T> work) {
        return execute(transactions, work, () -> {});
    }

    public static <T> T execute(TransactionTemplate transactions, TransactionCallback<T> work, Runnable rolledBack) {
        if (TransactionSynchronizationManager.isActualTransactionActive()) return transactions.execute(work);
        for (int attempt = 0; ; attempt++) {
            try { return transactions.execute(work); }
            catch (RuntimeException failure) {
                if (!isDeadlock(failure)) throw failure;
                rolledBack.run();
                if (attempt >= 2) throw failure;
                try { Thread.sleep(ThreadLocalRandom.current().nextLong(10, 41)); }
                catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    failure.addSuppressed(interrupted);
                    throw failure;
                }
            }
        }
    }

    public static void executeWithoutResult(TransactionTemplate transactions, Consumer<TransactionStatus> work) {
        execute(transactions, status -> { work.accept(status); return null; });
    }

    private static boolean isDeadlock(Throwable failure) {
        for (Throwable cause = failure; cause != null; cause = cause.getCause()) {
            if (cause instanceof SQLException sql && (sql.getErrorCode() == 1213 || "40001".equals(sql.getSQLState()))) return true;
        }
        return false;
    }
}
