package com.example.takeout.dao;

import com.example.takeout.model.BankCard;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * 银行卡数据访问（钱包页，只读展示）。
 *
 * 表内只有卡号后四位，不存在完整卡号；掩码在这里拼装，
 * 保证「完整卡号」这件事根本进不了实体层。
 */
@Repository
public class BankCardDao {

    private static final RowMapper<BankCard> MAPPER = (rs, i) -> new BankCard(
            rs.getLong("id"),
            rs.getLong("user_id"),
            rs.getString("bank_name"),
            rs.getString("card_type"),
            "**** **** **** " + rs.getString("card_no_last4"),
            rs.getInt("is_default"),
            rs.getInt("status"),
            rs.getString("create_time")
    );

    private final JdbcTemplate jdbc;

    public BankCardDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** 用户已绑定且未解绑的银行卡：默认卡置顶，其余按绑定时间倒序。 */
    public List<BankCard> listByUser(long userId) {
        return jdbc.query("SELECT * FROM bank_cards WHERE user_id = ? AND status = 1 " +
                "ORDER BY is_default DESC, id DESC", MAPPER, userId);
    }

    public int countByUser(long userId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM bank_cards WHERE user_id = ?", Integer.class, userId);
        return count == null ? 0 : count;
    }

    public void insert(long userId, String bankName, String cardType, String cardNoLast4,
                       int isDefault, String now) {
        jdbc.update("INSERT INTO bank_cards(user_id, bank_name, card_type, card_no_last4, " +
                        "is_default, status, create_time) VALUES(?,?,?,?,?,1,?)",
                userId, bankName, cardType, cardNoLast4, isDefault, now);
    }
}
