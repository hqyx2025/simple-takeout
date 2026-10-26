package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Address;
import com.example.takeout.model.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 收货地址上限（大纲 20.1：每人最多 20 个地址）。此前只有「默认地址唯一」落库，
 * 第 21 个地址会无限写入；这里钉住服务层在 insert 前拦下。
 */
class UserCenterAddressBoundaryTest {

    private final AddressDao addressDao = mock(AddressDao.class);
    private final UserDao userDao = mock(UserDao.class);
    private final UserCenterService service = new UserCenterService(
            null, null, addressDao, null, null, null, null, new ObjectMapper(), null, userDao, null);

    @BeforeEach
    void stubAccountLock() {
        when(userDao.findByIdForUpdate(1)).thenReturn(Optional.of(mock(User.class)));
        when(addressDao.listByUser(1)).thenReturn(List.of());
    }

    private void stubExisting(Address address) {
        when(addressDao.findByIdAndUser(address.id(), address.userId())).thenReturn(Optional.of(address));
        when(addressDao.update(anyLong(), anyLong(), anyString(), anyString(), anyString(), anyInt(),
                any(), any(), any(), any(), anyString())).thenReturn(true);
    }

    @Test
    void addPersistsCoordinatesAndStructuredAddress() {
        var saved = new Address(7, 1, "张三", "13800138000", "南宁学院东门 3栋1206", 0, "",
                22.5, 108.2, "南宁学院东门", "3栋1206", "学校");
        when(addressDao.insert(anyLong(), anyString(), anyString(), anyString(), anyInt(), any(), any(),
                any(), any(), anyString(), anyString())).thenReturn(7L);
        when(addressDao.findByIdAndUser(7, 1)).thenReturn(Optional.of(saved));

        Address result = service.addAddress(1, "张三", "13800138000", "ignored legacy text", 0,
                22.5, 108.2, "南宁学院东门", "3栋1206", "学校");

        assertEquals(7, result.id());
        verify(addressDao).insert(eq(1L), eq("张三"), eq("13800138000"), eq("南宁学院东门 3栋1206"), eq(0),
                eq(22.5), eq(108.2), eq("南宁学院东门"), eq("3栋1206"), eq("学校"), anyString());
        assertEquals("学校", result.tag());
    }

    @Test
    void retryingSameNormalizedAddressReturnsExistingRow() {
        var existing = new Address(7, 1, "张三", "13800138000", "南宁学院东门 3栋1206", 1, "",
                22.8167000, 108.3200000, "南宁学院东门", "3栋1206", "家");
        when(addressDao.listByUser(1)).thenReturn(List.of(existing));

        Address result = service.addAddress(1, "  张三 ", " 13800138000 ", "ignored", 0,
                22.81670004, 108.32000004, " 南宁学院东门 ", " 3栋1206 ", "公司");

        assertEquals(7, result.id());
        assertEquals("家", result.tag());
        verify(addressDao, never()).insert(anyLong(), anyString(), anyString(), anyString(), anyInt(),
                any(), any(), any(), any(), anyString(), anyString());
    }

    @Test
    void changedAddressCannotKeepOldCoordinates() {
        var existing = new Address(1, 1, "张三", "13800138000", "旧地址", 0, "", 30.5, 114.3);
        stubExisting(existing);
        service.updateAddress(1, 1, "张三", "13800138000", "新地址", 0, null, null);
        verify(addressDao).update(1, 1, "张三", "13800138000", "新地址", 0,
                null, null, null, null, "");
    }

    @Test
    void contactOnlyEditKeepsCoordinates() {
        var existing = new Address(1, 1, "张三", "13800138000", "原地址", 0, "", 30.5, 114.3);
        stubExisting(existing);
        service.updateAddress(1, 1, "李四", "13800138000", "原地址", 0, null, null);
        verify(addressDao).update(1, 1, "李四", "13800138000", "原地址", 0,
                30.5, 114.3, null, null, "");
    }

    @Test
    void legacyContactEditDoesNotEraseStructuredAddress() {
        var existing = new Address(1, 1, "张三", "13800138000", "南宁学院东门 3栋1206", 0, "",
                22.5, 108.2, "南宁学院东门", "3栋1206", "家");
        stubExisting(existing);

        service.updateAddress(1, 1, "李四", "13800138000", "南宁学院东门 3栋1206", 0, null, null);

        verify(addressDao).update(1, 1, "李四", "13800138000", "南宁学院东门 3栋1206", 0,
                22.5, 108.2, "南宁学院东门", "3栋1206", "家");
    }

    @Test
    void doorOnlyEditKeepsCoordinatesAndStructuredMapAddress() {
        var existing = new Address(1, 1, "张三", "13800138000", "南宁学院东门 3栋1206", 0, "",
                22.5, 108.2, "南宁学院东门", "3栋1206");
        stubExisting(existing);

        service.updateAddress(1, 1, "张三", "13800138000", "南宁学院东门 3栋1207", 0,
                null, null, "南宁学院东门", "3栋1207");

        verify(addressDao).update(1, 1, "张三", "13800138000", "南宁学院东门 3栋1207", 0,
                22.5, 108.2, "南宁学院东门", "3栋1207", "");
    }

    @Test
    void changedMapAddressWithoutNewPositionClearsCoordinates() {
        var existing = new Address(1, 1, "张三", "13800138000", "南宁学院东门 3栋1206", 0, "",
                22.5, 108.2, "南宁学院东门", "3栋1206");
        stubExisting(existing);

        service.updateAddress(1, 1, "张三", "13800138000", "南宁学院西门 3栋1206", 0,
                null, null, "南宁学院西门", "3栋1206");

        verify(addressDao).update(1, 1, "张三", "13800138000", "南宁学院西门 3栋1206", 0,
                null, null, "南宁学院西门", "3栋1206", "");
    }

    @Test
    void rejectsAddressWhenAlreadyAtTwenty() {
        when(addressDao.listByUser(1)).thenReturn(java.util.stream.IntStream.range(0, 20)
                .mapToObj(i -> new Address(i + 1, 1, "联系人" + i, "13800138000", "地址" + i, 0, ""))
                .toList());

        BizException error = assertThrows(BizException.class,
                () -> service.addAddress(1, "张三", "13800138000", "测试地址", 0));

        assertEquals("收货地址最多保存 20 个，请先删除部分地址", error.getMessage());
        verify(addressDao, never()).insert(anyLong(), anyString(), anyString(), anyString(), anyInt(), any(), any(),
                any(), any(), anyString(), anyString());
    }

    @Test
    void invalidDefaultTargetDoesNotReachDefaultSwitch() {
        when(addressDao.findByIdAndUser(999, 1)).thenReturn(Optional.empty());

        assertEquals("地址不存在", assertThrows(BizException.class,
                () -> service.setDefaultAddress(1, 999)).getMessage());

        verify(addressDao, never()).setDefault(anyLong(), anyLong());
    }

    @Test
    void foreignAddressCannotBeUpdatedOrClearOwnDefault() {
        when(addressDao.findByIdAndUser(8, 1)).thenReturn(Optional.empty());

        assertEquals("地址不存在", assertThrows(BizException.class,
                () -> service.updateAddress(1, 8, "张三", "13800138000", "测试地址", 1)).getMessage());

        verify(addressDao, never()).update(anyLong(), anyLong(), anyString(), anyString(), anyString(), anyInt(),
                any(), any(), any(), any(), anyString());
    }

    @Test
    void addressMutationsAreTransactional() throws Exception {
        assertNotNull(UserCenterService.class.getMethod("addAddress", long.class, String.class, String.class,
                String.class, int.class, Double.class, Double.class, String.class, String.class)
                .getAnnotation(Transactional.class));
        assertNotNull(UserCenterService.class.getMethod("updateAddress", long.class, long.class, String.class,
                String.class, String.class, int.class, Double.class, Double.class, String.class, String.class)
                .getAnnotation(Transactional.class));
        assertNotNull(UserCenterService.class.getMethod("setDefaultAddress", long.class, long.class)
                .getAnnotation(Transactional.class));
    }
}
