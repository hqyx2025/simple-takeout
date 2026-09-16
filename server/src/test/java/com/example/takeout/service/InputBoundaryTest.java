package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.AnnouncementDao;
import com.example.takeout.dao.BannerDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.dao.GoodsSpecDao;
import com.example.takeout.dao.SeckillDao;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.model.Store;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 文本输入的列宽边界：超长输入原先会直接写库、由 MySQL strict 抛列宽溢出变成 500，
 * 现在必须在服务层就以可读的 400 提示拒绝（列宽见 schema.sql）。
 */
class InputBoundaryTest {

    private static final long OWNER_ID = 99L;
    private static final long STORE_ID = 10L;

    private final StoreDao storeDao = mock(StoreDao.class);
    private final GoodsDao goodsDao = mock(GoodsDao.class);
    private final BannerDao bannerDao = mock(BannerDao.class);
    private final AnnouncementDao announcementDao = mock(AnnouncementDao.class);
    private final HotDataCacheService cache = mock(HotDataCacheService.class);

    private final StoreService storeService = new StoreService(storeDao, goodsDao, mock(GoodsSpecDao.class),
            mock(SeckillDao.class), new ObjectMapper(), cache);
    private final ContentService contentService = new ContentService(bannerDao, announcementDao, cache);

    @Test
    void createStoreRejectsOverlongNameAndNotice() {
        BizException nameError = assertThrows(BizException.class, () -> storeService.createStore(OWNER_ID,
                "店".repeat(129), 1, 3, 20, "30分钟", "", "北京市海淀区", 39.9, 116.4, 0));
        assertEquals("店铺名称最多 128 个字符", nameError.getMessage());
        verify(storeDao, never()).insert(any(Store.class));

        when(storeDao.categoryExists(1)).thenReturn(true);
        BizException noticeError = assertThrows(BizException.class, () -> storeService.createStore(OWNER_ID,
                "测试店", 1, 3, 20, "30分钟", "公".repeat(513), "北京市海淀区", 39.9, 116.4, 0));
        assertEquals("店铺公告最多 512 个字符", noticeError.getMessage());
        verify(storeDao, never()).insert(any(Store.class));
    }

    @Test
    void addGoodsRejectsOverlongNameAndDescription() {
        when(storeDao.findById(STORE_ID)).thenReturn(Optional.of(openStore()));
        when(storeDao.categoryExists(1)).thenReturn(true);

        BizException nameError = assertThrows(BizException.class,
                () -> storeService.addGoods(OWNER_ID, STORE_ID, goodsInput("商".repeat(129), "描述")));
        assertEquals("商品名称最多 128 个字符", nameError.getMessage());

        BizException descriptionError = assertThrows(BizException.class,
                () -> storeService.addGoods(OWNER_ID, STORE_ID, goodsInput("测试商品", "描".repeat(513))));
        assertEquals("商品描述最多 512 个字符", descriptionError.getMessage());
        verify(goodsDao, never()).insert(any());
    }

    @Test
    void createMerchantCategoryRejectsOverlongName() {
        when(storeDao.merchantCategoryNameExists(OWNER_ID, "分".repeat(33), 0)).thenReturn(false);

        BizException error = assertThrows(BizException.class,
                () -> storeService.createMerchantCategory(OWNER_ID, "分".repeat(33), 0));

        assertEquals("分类名称最多 32 个字符", error.getMessage());
    }

    // ============ 内容管理 ============

    @Test
    void createBannerRejectsOverlongSubtitle() {
        BizException error = assertThrows(BizException.class, () -> contentService.createBanner(
                "标题", "副".repeat(129), "", "", "NONE", "", 0));

        assertEquals("Banner 副标题最多 128 个字符", error.getMessage());
        verify(bannerDao, never()).insert(any(), any(), any(), any(), any(), any(), any(Integer.class), any());
    }

    @Test
    void updateBannerRejectsBlankTitleAndOverlongTitle() {
        // 旧实现把 null/空白标题当空串覆盖，PUT 只改 sort 就会清空标题
        BizException blank = assertThrows(BizException.class, () -> contentService.updateBanner(
                1, "   ", "副标题", "", "", "NONE", "", 0));
        assertEquals("Banner 标题不能为空", blank.getMessage());

        BizException tooLong = assertThrows(BizException.class, () -> contentService.updateBanner(
                1, "标".repeat(65), "副标题", "", "", "NONE", "", 0));
        assertEquals("Banner 标题最多 64 个字符", tooLong.getMessage());
        verify(bannerDao, never()).update(any(Long.class), any(), any(), any(), any(), any(), any(), any(Integer.class));
    }

    @Test
    void createAnnouncementRejectsOverlongContent() {
        BizException error = assertThrows(BizException.class,
                () -> contentService.createAnnouncement("公告标题", "内".repeat(1025)));

        assertEquals("公告内容最多 1024 个字符", error.getMessage());
        verify(announcementDao, never()).insert(any(), any(), any());
    }

    // ============ 夹具 ============

    private Store openStore() {
        return new Store(STORE_ID, "测试店", "", 4.5, 0, 3, 20, "30分钟", "1km", "[]", "",
                1, "[1]", OWNER_ID, 1, 0, "");
    }

    private StoreService.GoodsInput goodsInput(String name, String description) {
        return new StoreService.GoodsInput(name, description, 10, 0, "", 1, "", 1, 0, 99, false, List.of());
    }
}