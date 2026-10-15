package com.example.takeout.dao;

/** SQL expressions used while legacy VARCHAR timestamps and DATETIME shadows coexist. */
final class JdbcDateTimes {
    private static final String FORMAT = "%Y-%m-%d %H:%i:%s";
    static final String PARAMETER = "STR_TO_DATE(NULLIF(?, ''), '" + FORMAT + "')";

    private JdbcDateTimes() {
    }

    static String value(String column) {
        // An older instance may edit only the legacy value after the shadow has been written.
        // Prefer a shadow only when it still matches; empty legacy values retain their original meaning.
        return "(CASE WHEN DATE_FORMAT(" + column + "_dt, '" + FORMAT + "') = " + column +
                " THEN " + column + "_dt ELSE " + legacyValue(column) + " END)";
    }

    private static String legacyValue(String column) {
        // Guard parsing: strict MySQL turns an invalid-date warning inside UPDATE/DELETE into an error.
        String validShape = "^[1-9][0-9]{3}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])" +
                "( ([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9])?$";
        return "CASE WHEN " + column + " REGEXP '" + validShape + "' THEN CASE WHEN " +
                "CAST(SUBSTRING(" + column + ", 9, 2) AS UNSIGNED) <= DAY(LAST_DAY(CONCAT(LEFT(" + column +
                ", 7), '-01'))) THEN CASE WHEN LENGTH(" + column + ") = 10 THEN STR_TO_DATE(" + column +
                ", '%Y-%m-%d') ELSE STR_TO_DATE(" + column + ", '" + FORMAT +
                "') END ELSE NULL END ELSE NULL END";
    }
}
