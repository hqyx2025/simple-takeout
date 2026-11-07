package com.example.takeout.dao;

import com.example.takeout.service.PersonalDataCrypto;
import org.springframework.jdbc.core.JdbcTemplate;
import java.util.*;

/** Position-aware blind substrings preserve SQL LIKE search and database pagination without plaintext. */
final class PersonalPhoneIndex {
    private final JdbcTemplate jdbc;
    private final PersonalDataCrypto crypto;
    PersonalPhoneIndex(JdbcTemplate jdbc, PersonalDataCrypto crypto) { this.jdbc = jdbc; this.crypto = crypto; }

    void replace(long userId, String phone) {
        jdbc.update("DELETE FROM user_phone_search WHERE user_id=?", userId);
        insert(userId, phone);
    }

    void insert(long userId, String phone) {
        List<Object[]> entries = new ArrayList<>();
        int size = phone.codePointCount(0, phone.length());
        for (int start = 0; start < size; start++) for (int end = start + 1; end <= size; end++) {
            String part = phone.substring(phone.offsetByCodePoints(0, start), phone.offsetByCodePoints(0, end));
            entries.add(new Object[]{userId, start, end - start, crypto.hash("phone:gram", part)});
        }
        if (!entries.isEmpty()) jdbc.batchUpdate("INSERT INTO user_phone_search(user_id,start_pos,span,token) VALUES(?,?,?,?)", entries);
    }

    private record Segment(String text, int gap, boolean anyGap) {}

    String like(String keyword, List<Object> args) {
        List<Segment> segments = new ArrayList<>();
        String pattern = "%" + keyword.trim() + "%";
        StringBuilder literal = new StringBuilder();
        int gap = 0, minimum = 0; boolean any = false;
        for (int i = 0; i < pattern.length(); i++) {
            char ch = pattern.charAt(i);
            if (ch == '\\' && i + 1 < pattern.length()) { literal.append(pattern.charAt(++i)); continue; }
            if (ch != '%' && ch != '_') { literal.append(ch); continue; }
            if (!literal.isEmpty()) {
                String text = literal.toString();
                minimum += text.codePointCount(0, text.length());
                segments.add(new Segment(text, gap, any)); literal.setLength(0); gap = 0; any = false;
            }
            if (ch == '_') { gap++; minimum++; } else any = true;
        }
        if (!literal.isEmpty()) {
            String text = literal.toString(); minimum += text.codePointCount(0, text.length());
            segments.add(new Segment(text, gap, any)); gap = 0; any = false;
        }
        StringBuilder sql = new StringBuilder("(");
        if (minimum > 20) sql.append("FALSE");
        else if (segments.isEmpty()) sql.append("u.phone_length>=").append(gap);
        else {
            sql.append("EXISTS(SELECT 1 FROM user_phone_search p0 ");
            for (int i = 1; i < segments.size(); i++) sql.append("JOIN user_phone_search p").append(i).append(" ON p").append(i).append(".user_id=p0.user_id ");
            sql.append("WHERE p0.user_id=u.id ");
            for (int i = 0; i < segments.size(); i++) {
                Segment segment = segments.get(i);
                sql.append("AND p").append(i).append(".token=? AND p").append(i).append(".start_pos");
                if (i == 0) sql.append(">=").append(segment.gap());
                else sql.append(segment.anyGap() ? ">=" : "=").append("p").append(i - 1).append(".start_pos+p").append(i - 1).append(".span+").append(segment.gap());
                sql.append(' '); args.add(crypto.hash("phone:gram", segment.text()));
            }
            int last = segments.size() - 1;
            sql.append("AND u.phone_length").append(any ? ">=p" : "=p").append(last).append(".start_pos+p").append(last).append(".span+").append(gap).append(')');
        }
        sql.append(" OR (u.phone_encrypted IS NULL AND u.phone LIKE ?))"); args.add(pattern);
        return sql.toString();
    }
}
