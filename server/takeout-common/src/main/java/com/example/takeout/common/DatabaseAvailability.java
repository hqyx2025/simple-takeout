package com.example.takeout.common;

import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.dao.RecoverableDataAccessException;
import org.springframework.dao.TransientDataAccessResourceException;

/** 只识别连接、资源和超时故障；业务冲突、死锁、SQL 编写错误不触发可用性熔断。 */
public final class DatabaseAvailability {
    public static final String FAILURE_ATTRIBUTE = "takeout.database.availability-failure";
    private DatabaseAvailability() {}

    public static boolean unavailable(Throwable error) {
        for (int depth = 0; error != null && depth < 20; depth++, error = error.getCause()) {
            if (error instanceof DataAccessResourceFailureException || error instanceof QueryTimeoutException
                    || error instanceof RecoverableDataAccessException || error instanceof TransientDataAccessResourceException
                    || error instanceof java.sql.SQLTimeoutException || error instanceof java.sql.SQLTransientConnectionException
                    || error instanceof java.sql.SQLRecoverableException) return true;
            if (error instanceof java.sql.SQLException sql && sql.getSQLState() != null
                    && sql.getSQLState().startsWith("08")) return true;
        }
        return false;
    }
}
