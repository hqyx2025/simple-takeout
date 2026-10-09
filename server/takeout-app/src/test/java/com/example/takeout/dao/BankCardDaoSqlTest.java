package com.example.takeout.dao;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class BankCardDaoSqlTest {
    @Test
    void accountLockUsesStableUserRowEvenWhenNoCardsExist() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(), any(RowMapper.class), eq(7L))).thenReturn(List.of());

        assertFalse(new BankCardDao(jdbc).lockUser(7));
        verify(jdbc).query(eq("SELECT id FROM users WHERE id = ? FOR UPDATE"), any(RowMapper.class), eq(7L));
    }

    @Test
    void cardDeletionIsSoftScopedToOwnerAndClearsDefault() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        BankCardDao dao = new BankCardDao(jdbc);
        dao.delete(7, 11);
        dao.setDefault(7, 12);

        verify(jdbc).update("UPDATE bank_cards SET status = 0, is_default = 0 WHERE id = ? AND user_id = ? AND status = 1", 11L, 7L);
        verify(jdbc).update("UPDATE bank_cards SET is_default = CASE WHEN id = ? THEN 1 ELSE 0 END WHERE user_id = ? AND status = 1", 12L, 7L);
    }

    @Test
    void listingFiltersDeletedRecordsWhileHistoricalCountIncludesThem() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(), any(RowMapper.class), eq(7L))).thenReturn(List.of());
        when(jdbc.queryForObject(anyString(), eq(Integer.class), eq(7L))).thenReturn(2);
        BankCardDao dao = new BankCardDao(jdbc);

        assertEquals(0, dao.listByUser(7).size());
        assertEquals(2, dao.countByUser(7));
        verify(jdbc).query(eq("SELECT * FROM bank_cards WHERE user_id = ? AND status = 1 ORDER BY is_default DESC, id DESC"),
                any(RowMapper.class), eq(7L));
        verify(jdbc).queryForObject("SELECT COUNT(*) FROM bank_cards WHERE user_id = ?", Integer.class, 7L);
    }

    @Test
    void duplicateLookupIncludesAccountAndOnlyActiveMatchingInformation() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), eq(Integer.class), eq(7L), eq("招商银行"), eq("储蓄卡"), eq("0123"))).thenReturn(1);

        assertTrue(new BankCardDao(jdbc).activeInfoExists(7, "招商银行", "储蓄卡", "0123"));
        verify(jdbc).queryForObject("SELECT COUNT(*) FROM bank_cards WHERE user_id = ? AND status = 1 "
                + "AND bank_name = ? AND card_type = ? AND card_no_last4 = ?", Integer.class, 7L, "招商银行", "储蓄卡", "0123");
    }

    @Test
    void revealReadsOnlyActiveOwnedCiphertextAndLegacyNullIsEmpty() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(), any(RowMapper.class), eq(11L), eq(7L))).thenAnswer(invocation -> {
            RowMapper<String> mapper = invocation.getArgument(1);
            var resultSet = mock(java.sql.ResultSet.class);
            when(resultSet.getString("full_card_encrypted")).thenReturn(null);
            return List.of(mapper.mapRow(resultSet, 0));
        });

        assertEquals("", new BankCardDao(jdbc).findEncryptedCardNumber(7, 11).orElseThrow());
        verify(jdbc).query(eq("SELECT full_card_encrypted FROM bank_cards WHERE id = ? AND user_id = ? AND status = 1"),
                any(RowMapper.class), eq(11L), eq(7L));
    }
}
