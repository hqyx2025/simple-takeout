package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.BankCardDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.BankCard;
import com.example.takeout.model.User;
import com.example.takeout.security.PasswordUtil;
import com.example.takeout.security.PaymentPasswordUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class UserCenterFullBankCardTest {
    private static final long USER = 7;
    private static final String NUMBER = "6225888888880123";
    private final BankCardDao cards = mock(BankCardDao.class);
    private final UserDao users = mock(UserDao.class);
    private final BankCardCrypto crypto = new BankCardCrypto("unit-test-only-server-secret");
    private final UserCenterService service = new UserCenterService(null, null, null, null, null, null,
            cards, new ObjectMapper(), null, users, crypto);

    @Test
    void fullNumberIsNormalizedEncryptedAndOnlyMaskedResponseIsReturned() throws Exception {
        when(cards.lockUser(USER)).thenReturn(true);
        when(cards.listEncryptedCardNumbers(USER)).thenReturn(List.of());
        when(cards.listByUser(USER)).thenReturn(List.of());
        when(cards.insert(eq(USER), eq("招商银行"), eq("储蓄卡"), eq("0123"), anyString(), eq(1), anyString())).thenReturn(11L);
        BankCard expected = new BankCard(11, USER, "招商银行", "储蓄卡", "**** **** **** 0123", 1, 1, "now");
        when(cards.findById(11)).thenReturn(Optional.of(expected));

        BankCard returned = service.addBankCardFull(USER, "招商银行", "储蓄卡", "6225 8888 8888 0123");
        ArgumentCaptor<String> encrypted = ArgumentCaptor.forClass(String.class);
        verify(cards).insert(eq(USER), eq("招商银行"), eq("储蓄卡"), eq("0123"), encrypted.capture(), eq(1), anyString());
        assertFalse(encrypted.getValue().contains(NUMBER));
        assertEquals(NUMBER, crypto.decrypt(encrypted.getValue()));
        assertFalse(new ObjectMapper().writeValueAsString(returned).contains(NUMBER));
    }

    @Test
    void differentCardsWithSameLastFourDigitsCanBeAddedButSameFullNumberIsRejected() {
        when(cards.lockUser(USER)).thenReturn(true);
        when(cards.listEncryptedCardNumbers(USER)).thenReturn(List.of(crypto.encrypt("6225666666660123")));
        when(cards.listByUser(USER)).thenReturn(List.of());
        when(cards.insert(eq(USER), anyString(), anyString(), eq("0123"), anyString(), anyInt(), anyString())).thenReturn(11L);
        when(cards.findById(11)).thenReturn(Optional.of(new BankCard(11, USER, "招商银行", "储蓄卡", "**** **** **** 0123", 0, 1, "now")));
        assertNotNull(service.addBankCardFull(USER, "招商银行", "储蓄卡", NUMBER));
        when(cards.listEncryptedCardNumbers(USER)).thenReturn(List.of(crypto.encrypt(NUMBER)));
        assertEquals("已添加该银行卡，请勿重复添加", assertThrows(BizException.class,
                () -> service.addBankCardFull(USER, "招商银行", "储蓄卡", NUMBER)).getMessage());
    }

    @Test
    void invalidFullNumberIsRejectedBeforeDatabaseAccess() {
        for (String number : new String[]{null, "", "0123", "1".repeat(15), "1".repeat(20), "622588888888abcd", "６２２５８８８８８８８８０１２３"}) {
            assertThrows(BizException.class, () -> service.addBankCardFull(USER, "招商银行", "储蓄卡", number));
        }
        verifyNoInteractions(cards, users);
    }

    @Test
    void validPaymentPasswordRevealsOnlyOwnedActiveCard() {
        when(users.findById(USER)).thenReturn(Optional.of(user(PaymentPasswordUtil.hash("135790"))));
        when(cards.findEncryptedCardNumber(USER, 11)).thenReturn(Optional.of(crypto.encrypt(NUMBER)));
        assertEquals(NUMBER, service.revealBankCard(USER, 11, "135790"));
        verify(cards).findEncryptedCardNumber(USER, 11);
    }

    @Test
    void wrongPasswordOrUnsetPasswordNeverReadsCiphertext() {
        when(users.findById(USER)).thenReturn(Optional.of(user(PaymentPasswordUtil.hash("135790"))));
        assertEquals("支付密码不正确", assertThrows(BizException.class,
                () -> service.revealBankCard(USER, 11, "999999")).getMessage());
        when(users.findById(USER)).thenReturn(Optional.of(user(null)));
        assertEquals("尚未设置支付密码，请先设置支付密码", assertThrows(BizException.class,
                () -> service.revealBankCard(USER, 11, "135790")).getMessage());
        verifyNoInteractions(cards);
    }

    @Test
    void otherAccountsDeletedCardAndLegacyMissingFullNumberCannotBeRevealed() {
        when(users.findById(USER)).thenReturn(Optional.of(user(PaymentPasswordUtil.hash("135790"))));
        when(cards.findEncryptedCardNumber(USER, 11)).thenReturn(Optional.empty());
        assertEquals(403, assertThrows(BizException.class, () -> service.revealBankCard(USER, 11, "135790")).getCode());
        when(cards.findEncryptedCardNumber(USER, 12)).thenReturn(Optional.of(""));
        assertEquals("该银行卡未录入完整卡号，请重新添加", assertThrows(BizException.class,
                () -> service.revealBankCard(USER, 12, "135790")).getMessage());
    }

    @Test
    void userResponseDoesNotExposePaymentHash() throws Exception {
        String hash = PaymentPasswordUtil.hash("135790");
        String json = new ObjectMapper().writeValueAsString(user(hash).safe());
        assertFalse(json.contains(hash));
        assertFalse(json.contains("paymentPasswordHash"));
    }

    private User user(String paymentHash) {
        return new User(USER, "用户", "", "13800138000", PasswordUtil.hash("login-secret"), 0,
                1, 20, "now", "", paymentHash);
    }
}
