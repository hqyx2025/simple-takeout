package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.RiderDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Rider;
import com.example.takeout.model.User;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 骑手端（四端改造）安全与建档用例
 */
class RiderServiceSecurityTest {

    private final RiderDao riderDao = mock(RiderDao.class);
    private final UserDao userDao = mock(UserDao.class);
    private final RiderService service = new RiderService(riderDao, userDao);

    @Test
    void rejectsNonRiderAccount() {
        User customer = new User(1, "用户", "", "13800138000", "", 0, 20, "now");
        when(userDao.findById(1)).thenReturn(Optional.of(customer));

        BizException error = assertThrows(BizException.class, () -> service.profile(1));

        assertEquals(403, error.getCode());
    }

    @Test
    void createsRiderProfileOnFirstAccess() {
        User riderUser = new User(9, "骑手小王", "", "13900139000", "", 3, 0, "now");
        Rider created = new Rider(5, 9, "骑手小王", "13900139000", 0, 0, 0.0, 1, "now");
        when(userDao.findById(9)).thenReturn(Optional.of(riderUser));
        when(riderDao.findByUserId(9)).thenReturn(Optional.empty());
        when(riderDao.insert(ArgumentMatchers.eq(9L), ArgumentMatchers.eq("骑手小王"),
                ArgumentMatchers.eq("13900139000"), ArgumentMatchers.anyString())).thenReturn(5L);
        when(riderDao.findById(5)).thenReturn(Optional.of(created));

        Rider result = service.profile(9);

        assertEquals(5L, result.id());
        assertEquals(0, result.online());
    }

    @Test
    void setOnlineTogglesRiderFlag() {
        User riderUser = new User(9, "骑手小王", "", "13900139000", "", 3, 0, "now");
        Rider offline = new Rider(5, 9, "骑手小王", "13900139000", 0, 3, 25.5, 1, "now");
        Rider online = new Rider(5, 9, "骑手小王", "13900139000", 1, 3, 25.5, 1, "now");
        when(userDao.findById(9)).thenReturn(Optional.of(riderUser));
        when(riderDao.findByUserId(9)).thenReturn(Optional.of(offline));
        when(riderDao.findById(5)).thenReturn(Optional.of(online));

        Rider result = service.setOnline(9, 1);

        assertEquals(1, result.online());
        verify(riderDao).updateOnline(5, 1);
    }
}
