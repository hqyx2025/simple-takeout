package com.example.takeout.model;

import java.util.List;

/** 平台运营统计，金额均为数据库实时聚合结果。 */
public record AdminStatistics(
        long totalUsers,
        long totalMerchants,
        long totalStores,
        long totalGoods,
        long totalOrders,
        double totalGmv,
        double settledAmount,
        double pendingEscrowAmount,
        long todayOrders,
        double todayGmv,
        List<HotGoods> hotGoods
) {
    public record HotGoods(
            long goodsId,
            String goodsName,
            long storeId,
            String storeName,
            int sales,
            double price,
            int status
    ) {
    }

    public record TrendPoint(String date, long orderCount, double gmv) {
    }

    public record OrderStatusCount(int status, long count) {
    }

    public record TopStore(long storeId, String storeName, double gmv, long orderCount) {
    }
}
