package com.example.takeout.service;

import com.example.takeout.dao.AdminStatsDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.RefundDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.AdminProduct;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 管理端商品分页口径：pageSize 收敛到 [1,100]、offset 按 (page-1)*size 计算、hasMore 由 page*size<total 判定。
 */
class AdminServiceProductPagingTest {

    private final GoodsDao goodsDao = mock(GoodsDao.class);
    private final AdminService service = new AdminService(mock(StoreDao.class), mock(OrderDao.class),
            mock(UserDao.class), goodsDao, mock(RefundDao.class), mock(OrderService.class),
            mock(AdminStatsDao.class), mock(HotDataCacheService.class),
            mock(com.example.takeout.service.mq.DomainEventPublisher.class));

    private AdminProduct product(long id) {
        return new AdminProduct(id, 10L, "测试店", "商品" + id, "", 1.0, 1.0, "", 1, 0, 0, 0, 5.0, "", 1, "");
    }

    @Test
    void computesOffsetAndHasMore() {
        when(goodsDao.countForAdmin("面", null)).thenReturn(120);
        when(goodsDao.listForAdmin("面", null, 50, 50)).thenReturn(List.of(product(1)));

        AdminService.ProductPage page = service.products("面", null, 2, 50);

        verify(goodsDao).listForAdmin("面", null, 50, 50);
        assertEquals(50, page.pageSize());
        assertEquals(2, page.page());
        assertEquals(120, page.total());
        assertTrue(page.hasMore(), "2*50 < 120 应还有下一页");
        assertEquals(1, page.list().size());
    }

    @Test
    void hasMoreFalseOnLastPage() {
        when(goodsDao.countForAdmin("面", null)).thenReturn(100);
        when(goodsDao.listForAdmin("面", null, 50, 50)).thenReturn(List.of(product(1)));

        AdminService.ProductPage page = service.products("面", null, 2, 50);

        assertFalse(page.hasMore(), "2*50 == 100 已到末页");
    }

    @Test
    void clampsPageSizeAndPageNumber() {
        when(goodsDao.countForAdmin(null, null)).thenReturn(5);
        when(goodsDao.listForAdmin(null, null, 100, 0)).thenReturn(List.of(product(1)));

        AdminService.ProductPage page = service.products(null, null, 0, 9999);

        verify(goodsDao).listForAdmin(null, null, 100, 0);
        assertEquals(100, page.pageSize(), "超上限 pageSize 应收敛到 100");
        assertEquals(1, page.page(), "非法 page 应回退到 1");
    }
}