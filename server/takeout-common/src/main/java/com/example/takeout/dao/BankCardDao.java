package com.example.takeout.dao;

import com.example.takeout.model.BankCard;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * 钱包银行卡记录；写入由用户中心事务持有账号行锁后执行。
 *
 * 完整卡号以密文存储且只通过受控揭示方法读取；实体层始终只拼装掩码。
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

    /** 锁账号行而非卡片行，保证没有卡片时并发添加首卡也会串行。 */
    public boolean lockUser(long userId) {
        return !jdbc.query("SELECT id FROM users WHERE id = ? FOR UPDATE",
                (rs, i) -> rs.getLong("id"), userId).isEmpty();
    }

    public Optional<BankCard> findById(long id) {
        return jdbc.query("SELECT * FROM bank_cards WHERE id = ?", MAPPER, id).stream().findFirst();
    }

    /** 仅供支付密码已通过的揭示流程读取密文，不映射到对外银行卡实体。 */
    public Optional<String> findEncryptedCardNumber(long userId, long id) {
        return jdbc.query("SELECT full_card_encrypted FROM bank_cards "
                        + "WHERE id = ? AND user_id = ? AND status = 1",
                (rs, i) -> java.util.Objects.requireNonNullElse(rs.getString("full_card_encrypted"), ""),
                id, userId).stream().findFirst();
    }

    /** 在账号行锁内比较加密保存的完整卡号，不用尾号判断重复，允许不同银行卡同尾号。 */
    public List<String> listEncryptedCardNumbers(long userId) {
        return jdbc.query("SELECT full_card_encrypted FROM bank_cards WHERE user_id = ? AND status = 1 "
                        + "AND full_card_encrypted IS NOT NULL AND full_card_encrypted <> ''",
                (rs, i) -> rs.getString("full_card_encrypted"), userId);
    }

    public boolean activeInfoExists(long userId, String bankName, String cardType, String cardNoLast4) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM bank_cards WHERE user_id = ? AND status = 1 "
                        + "AND bank_name = ? AND card_type = ? AND card_no_last4 = ?",
                Integer.class, userId, bankName, cardType, cardNoLast4);
        return count != null && count > 0;
    }

    public long insert(long userId, String bankName, String cardType, String cardNoLast4,
                       int isDefault, String now) {
        jdbc.update("INSERT INTO bank_cards(user_id, bank_name, card_type, card_no_last4, " +
                        "is_default, status, create_time) VALUES(?,?,?,?,?,1,?)",
                userId, bankName, cardType, cardNoLast4, isDefault, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public long insert(long userId, String bankName, String cardType, String cardNoLast4,
                       String fullCardEncrypted, int isDefault, String now) {
        jdbc.update("INSERT INTO bank_cards(user_id, bank_name, card_type, card_no_last4, "
                        + "full_card_encrypted, is_default, status, create_time) VALUES(?,?,?,?,?,?,1,?)",
                userId, bankName, cardType, cardNoLast4, fullCardEncrypted, isDefault, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    /** 保留解绑记录，避免启动时再次为已清空银行卡的账号补演示卡。 */
    public void delete(long userId, long id) {
        jdbc.update("UPDATE bank_cards SET status = 0, is_default = 0 WHERE id = ? AND user_id = ? AND status = 1",
                id, userId);
    }

    public void setDefault(long userId, long id) {
        jdbc.update("UPDATE bank_cards SET is_default = CASE WHEN id = ? THEN 1 ELSE 0 END "
                + "WHERE user_id = ? AND status = 1", id, userId);
    }
}
