package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.CouponDao;
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

/**
 * 优惠券领取限领契约：同一活动（userId+storeId+name 唯一键）每人终身限领一次。
 */
class UserCenterCouponClaimTest {

    private final CouponDao couponDao = mock(CouponDao.class);
    private final UserCouponDao userCouponDao = mock(UserCouponDao.class);
    private final UserCenterService service = new UserCenterService(
            couponDao, null, null, null, null, null, null, new ObjectMapper(), userCouponDao);

    @Test
    void claimCouponRejectsSecondClaimOfSameCampaign() {
        when(userCouponDao.exists(1L, 0L, "满10减2")).thenReturn(true);

        BizException error = assertThrows(BizException.class,
                () -> service.claimCoupon(1, 0, "", 10, 2));

        assertEquals("该优惠券每人限领一次，请勿重复领取", error.getMessage());
        verify(couponDao, never()).insert(anyLong(), anyLong(), anyString(),
                anyDouble(), anyDouble(), anyString(), anyString(), anyString());
    }
}
