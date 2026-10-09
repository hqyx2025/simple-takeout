package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.BankCardDao;
import com.example.takeout.model.BankCard;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class UserCenterBankCardTest {
    private static final long USER = 7;
    private final BankCardDao cards = mock(BankCardDao.class);
    private final UserCenterService service = new UserCenterService(
            null, null, null, null, null, null, cards, new ObjectMapper(), null);

    @Test
    void firstActiveCardIsDefaultAndReturnsMaskedInformation() {
        when(cards.lockUser(USER)).thenReturn(true);
        when(cards.listByUser(USER)).thenReturn(List.of());
        when(cards.countByUser(USER)).thenReturn(3); // 解绑历史不影响重新添加后的首卡默认。
        when(cards.insert(eq(USER), eq("招商银行"), eq("储蓄卡"), eq("0123"), eq(1), anyString())).thenReturn(11L);
        BankCard saved = card(11, USER, 1, 1);
        when(cards.findById(11)).thenReturn(Optional.of(saved));

        assertEquals(saved, service.addBankCard(USER, " 招商银行 ", " 储蓄卡 ", "0123"));
        assertEquals("**** **** **** 0123", saved.cardNoMasked());
        var order = inOrder(cards);
        order.verify(cards).lockUser(USER);
        order.verify(cards).activeInfoExists(USER, "招商银行", "储蓄卡", "0123");
        order.verify(cards).listByUser(USER);
        order.verify(cards).insert(eq(USER), eq("招商银行"), eq("储蓄卡"), eq("0123"), eq(1), anyString());
    }

    @Test
    void laterCardIsNonDefaultAndExistingDefaultIsNotChanged() {
        when(cards.lockUser(USER)).thenReturn(true);
        when(cards.listByUser(USER)).thenReturn(List.of(card(10, USER, 1, 1)));
        when(cards.insert(eq(USER), eq("招商银行"), eq("信用卡"), eq("0123"), eq(0), anyString())).thenReturn(11L);
        when(cards.findById(11)).thenReturn(Optional.of(card(11, USER, 0, 1)));

        assertEquals(0, service.addBankCard(USER, "招商银行", "信用卡", "0123").isDefault());
        verify(cards, never()).setDefault(anyLong(), anyLong());
    }

    @Test
    void duplicateActiveInformationIsRejectedInsideAccountLock() {
        when(cards.lockUser(USER)).thenReturn(true);
        when(cards.activeInfoExists(USER, "招商银行", "储蓄卡", "0123")).thenReturn(true);

        BizException error = assertThrows(BizException.class,
                () -> service.addBankCard(USER, "招商银行", "储蓄卡", "0123"));
        assertEquals("已添加相同银行、卡类型和尾号的信息，请勿重复添加", error.getMessage());
        verify(cards, never()).insert(anyLong(), anyString(), anyString(), anyString(), anyInt(), anyString());
    }

    @Test
    void invalidInputsAreRejectedBeforeAnyDatabaseAccess() {
        for (String bank : List.of("", " ", "银".repeat(65), "银行\n名称")) {
            assertThrows(BizException.class, () -> service.addBankCard(USER, bank, "储蓄卡", "0123"));
        }
        assertThrows(BizException.class, () -> service.addBankCard(USER, null, "储蓄卡", "0123"));
        for (String type : List.of("", "借记卡", "其它")) {
            assertThrows(BizException.class, () -> service.addBankCard(USER, "招商银行", type, "0123"));
        }
        assertThrows(BizException.class, () -> service.addBankCard(USER, "招商银行", null, "0123"));
        for (String last4 : List.of("", "123", "12345", "１２３４", "1a34", " 1234", "1234 ", "6225888888881234")) {
            assertThrows(BizException.class, () -> service.addBankCard(USER, "招商银行", "储蓄卡", last4));
        }
        assertThrows(BizException.class, () -> service.addBankCard(USER, "招商银行", "储蓄卡", null));
        verifyNoInteractions(cards);
    }

    @Test
    void deletingAnotherAccountsCardIsForbiddenIncludingAnAlreadyDeletedCard() {
        when(cards.lockUser(USER)).thenReturn(true);
        when(cards.findById(20)).thenReturn(Optional.of(card(20, 99, 1, 1)), Optional.of(card(20, 99, 0, 0)));

        assertEquals(403, assertThrows(BizException.class, () -> service.deleteBankCard(USER, 20)).getCode());
        assertEquals(403, assertThrows(BizException.class, () -> service.deleteBankCard(USER, 20)).getCode());
        verify(cards, never()).delete(anyLong(), anyLong());
    }

    @Test
    void deletingDefaultCardSelectsOneRemainingCardWithinSameTransaction() {
        when(cards.lockUser(USER)).thenReturn(true);
        when(cards.findById(10)).thenReturn(Optional.of(card(10, USER, 1, 1)));
        when(cards.listByUser(USER)).thenReturn(List.of(card(12, USER, 0, 1), card(11, USER, 0, 1)));

        service.deleteBankCard(USER, 10);
        var order = inOrder(cards);
        order.verify(cards).lockUser(USER);
        order.verify(cards).findById(10);
        order.verify(cards).delete(USER, 10);
        order.verify(cards).listByUser(USER);
        order.verify(cards).setDefault(USER, 12);
    }

    @Test
    void deletingNonDefaultCardPreservesTheDefaultAndRepeatDeleteIsIdempotent() {
        when(cards.lockUser(USER)).thenReturn(true);
        when(cards.findById(11)).thenReturn(Optional.of(card(11, USER, 0, 1)), Optional.of(card(11, USER, 0, 0)));

        service.deleteBankCard(USER, 11);
        service.deleteBankCard(USER, 11);
        verify(cards).delete(USER, 11);
        verify(cards, never()).setDefault(anyLong(), anyLong());
        verify(cards, never()).listByUser(anyLong());
    }

    @Test
    void deletingLastCardLeavesNoDefaultAndDoesNotRecreateDemoCards() {
        when(cards.lockUser(USER)).thenReturn(true);
        when(cards.findById(10)).thenReturn(Optional.of(card(10, USER, 1, 1)));
        when(cards.listByUser(USER)).thenReturn(List.of());

        service.deleteBankCard(USER, 10);
        verify(cards).delete(USER, 10);
        verify(cards, never()).setDefault(anyLong(), anyLong());
        verify(cards, never()).insert(anyLong(), anyString(), anyString(), anyString(), anyInt(), anyString());
    }

    @Test
    void missingAccountOrMissingCardCannotBeChanged() {
        assertEquals(401, assertThrows(BizException.class,
                () -> service.addBankCard(USER, "招商银行", "储蓄卡", "0123")).getCode());
        when(cards.lockUser(USER)).thenReturn(true);
        assertEquals(404, assertThrows(BizException.class, () -> service.deleteBankCard(USER, 20)).getCode());
        assertEquals(400, assertThrows(BizException.class, () -> service.deleteBankCard(USER, 0)).getCode());
        verify(cards, never()).delete(anyLong(), anyLong());
    }

    @Test
    void writesAreTransactionalSoAccountLockSpansAllCardChanges() throws Exception {
        assertNotNull(UserCenterService.class.getMethod("addBankCard", long.class, String.class, String.class, String.class)
                .getAnnotation(Transactional.class));
        assertNotNull(UserCenterService.class.getMethod("deleteBankCard", long.class, long.class)
                .getAnnotation(Transactional.class));
    }

    private BankCard card(long id, long userId, int isDefault, int status) {
        return new BankCard(id, userId, "招商银行", "储蓄卡", "**** **** **** 0123", isDefault, status, "2026-10-08 12:00:00");
    }
}
