package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AddressDao;
import com.example.takeout.model.Address;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.stream.IntStream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
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
    private final UserCenterService service = new UserCenterService(
            null, null, addressDao, null, null, null, null, new ObjectMapper());

    @Test
    void rejectsAddressWhenAlreadyAtTwenty() {
        List<Address> twenty = IntStream.range(0, 20)
                .mapToObj(i -> new Address(i + 1, 1, "张三", "13800138000", "测试地址", 0, ""))
                .toList();
        when(addressDao.listByUser(1)).thenReturn(twenty);

        BizException error = assertThrows(BizException.class,
                () -> service.addAddress(1, "张三", "13800138000", "测试地址", 0));

        assertEquals("收货地址最多保存 20 个，请先删除部分地址", error.getMessage());
        verify(addressDao, never()).insert(anyLong(), anyString(), anyString(), anyString(), anyInt(), anyString());
    }
}