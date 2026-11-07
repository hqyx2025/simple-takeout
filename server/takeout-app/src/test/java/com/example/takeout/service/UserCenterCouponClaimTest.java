package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.CouponDao;
import com.example.takeout.dao.CouponStockDao;
import com.example.takeout.dao.UserCouponDao;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.doThrow;

/**
 * 优惠券领取限领契约：同一活动（userId+storeId+name 唯一键）每人终身限领一次。
 */
class UserCenterCouponClaimTest {

    private final CouponDao couponDao = mock(CouponDao.class);
    private final UserCouponDao userCouponDao = mock(UserCouponDao.class);
    private final CouponStockDao stock = mock(CouponStockDao.class);
    private final UserCenterService service = new UserCenterService(
            couponDao, null, null, null, null, null, null, new ObjectMapper(), userCouponDao, null, null, stock);

    @Test
    void claimCouponRejectsSecondClaimOfSameCampaign() {
        when(userCouponDao.exists(1L, 0L, "满10减2")).thenReturn(true);

        BizException error = assertThrows(BizException.class,
                () -> service.claimCoupon(1, 0, "", 10, 2));

        assertEquals("该优惠券每人限领一次，请勿重复领取", error.getMessage());
        verify(couponDao, never()).insert(anyLong(), anyLong(), anyString(),
                anyDouble(), anyDouble(), anyString(), anyString(), anyString());
    }

    @Test
    void concurrentDuplicateDoesNotInsertCouponBeforeReservingClaim() {
        when(stock.hasAvailable("满10减2")).thenReturn(true);
        doThrow(new org.springframework.dao.DuplicateKeyException("duplicate"))
                .when(userCouponDao).insert(anyLong(), anyLong(), anyString(), anyDouble(), anyDouble(), anyString(), anyString());

        assertThrows(BizException.class, () -> service.claimCoupon(1, 0, "", 10, 2));

        verify(couponDao, never()).insert(anyLong(), anyLong(), anyString(),
                anyDouble(), anyDouble(), anyString(), anyString(), anyString());
    }

    @Test
    void successfulClaimReservesFirstAndReturnsCouponWithoutListingHistory() {
        when(stock.hasAvailable("满10减2")).thenReturn(true);
        when(stock.reserve("满10减2", 1)).thenReturn(true);
        when(couponDao.insert(anyLong(), anyLong(), anyString(), anyDouble(), anyDouble(), anyString(), anyString(), anyString()))
                .thenReturn(42L);

        var coupon = service.claimCoupon(1, 0, "untrusted", 10, 2);

        assertEquals(42L, coupon.id());
        assertEquals("满10减2", coupon.name());
        var calls = inOrder(userCouponDao, couponDao);
        calls.verify(userCouponDao).insert(anyLong(), anyLong(), anyString(), anyDouble(), anyDouble(), anyString(), anyString());
        calls.verify(couponDao).insert(anyLong(), anyLong(), anyString(), anyDouble(), anyDouble(), anyString(), anyString(), anyString());
        verify(couponDao, never()).listByUser(anyLong());
    }

    @Test
    void listingOnlyExpiresCurrentAccountCoupons() {
        service.listCoupons(7);
        verify(couponDao).expireOutdated(org.mockito.ArgumentMatchers.eq(7L), anyString());
    }

    @Test
    void invalidStoreCannotCreateAnotherClaimScope() {
        assertThrows(BizException.class, () -> service.claimCoupon(1, -1, "", 10, 2));
        org.mockito.Mockito.verifyNoInteractions(userCouponDao, stock, couponDao);
    }

    @Test
    void soldOutCampaignRejectsWithoutWritingClaimLedger() {
        assertEquals(409, assertThrows(BizException.class, () -> service.claimCoupon(1, 0, "", 10, 2)).getCode());
        verify(userCouponDao, never()).insert(anyLong(), anyLong(), anyString(), anyDouble(), anyDouble(), anyString(), anyString());
        org.mockito.Mockito.verifyNoInteractions(couponDao);
        verify(stock, never()).reserve(anyString(), anyLong());
    }
}
