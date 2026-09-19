package com.example.takeout.model;

/**
 * 限时秒杀：时间窗口内该菜品下单自动按秒杀价结算，quota 为秒杀名额（sold 为已售份数）。
 */
public record Seckill(
        long id,
        long goodsId,
        long storeId,
        double price,
        int quota,
        int sold,
        String startTime,
        String endTime,
        int status,
        String createTime
) {

    /** 秒杀活动视图：附带菜品与店铺信息，供首页秒杀专区渲染。 */
    public record SeckillView(
            long id,
            long goodsId,
            String goodsName,
            String image,
            double originalPrice,
            double price,
            int quota,
            int sold,
            String startTime,
            String endTime,
            long storeId,
            String storeName,
            String storeDistance,
            long remainSeconds
    ) {
    }
}
