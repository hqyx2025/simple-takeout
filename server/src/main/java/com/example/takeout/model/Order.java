package com.example.takeout.model;

import java.util.List;

/**
 * 订单（status：0待付款 1待接单 2制作中 3配送中 4已送达 5已取消 6退款中）
 * items/address 以 JSON 字符串存储，DTO 输出转为结构体
 */
public record Order(
        long id,
        String orderNo,
        long userId,
        long storeId,
        String storeName,
        int status,
        String items,
        String address,
        double goodsAmount,
        double deliveryFee,
        double discount,
        double payAmount,
        String remark,
        int reviewed,
        int escrowStatus,
        String createTime,
        String payTime,
        String acceptTime,
        String deliverTime,
        String completeTime,
        String expectTime,
        long couponId
) {
    /**
     * 订单商品项（对应客户端 CartItem 结构；多规格下单记录 specId/specName 规格快照，
     * 秒杀下单记录 seckillId 以便取消时归还秒杀名额）
     */
    public record OrderItem(
            long goodsId,
            String goodsName,
            double price,
            int quantity,
            String image,
            long specId,
            String specName,
            long seckillId
    ) {

        public OrderItem {
            // 老订单 JSON 无 spec/seckill 字段，Jackson 反序列化后为 null，统一归一为空串
            specName = specName == null ? "" : specName;
        }

        /** 兼容旧调用：无规格、非秒杀商品项。 */
        public OrderItem(long goodsId, String goodsName, double price, int quantity, String image) {
            this(goodsId, goodsName, price, quantity, image, 0, "", 0);
        }

        /** 订单项展示名：多规格菜品追加「(规格)」。 */
        public String displayName() {
            return specName == null || specName.isEmpty() ? goodsName : goodsName + "(" + specName + ")";
        }
    }

    /**
     * 收货地址（对应客户端 Address 结构）
     */
    public record AddressInfo(
            long addressId,
            String name,
            String phone,
            String detail
    ) {
    }

    /**
     * 视图模型：items/address 解析为结构体；payDeadline 为待付款订单的支付截止时间（非待付款为空串）；
     * payDeadlineEpochMs 为服务端计算的毫秒时间戳，避免前端解析字符串时区问题
     */
    public record OrderView(
            long id,
            String orderNo,
            long userId,
            long storeId,
            String storeName,
            int status,
            List<OrderItem> items,
            AddressInfo address,
            double goodsAmount,
            double deliveryFee,
            double discount,
            double payAmount,
            String remark,
            int reviewed,
            int escrowStatus,
            String createTime,
            String payTime,
            String acceptTime,
            String deliverTime,
            String completeTime,
            String expectTime,
            long couponId,
            String payDeadline,
            long payDeadlineEpochMs,
            String riderName,
            String riderPhone,
            String readyTime
    ) {
    }

    public OrderView toView(List<OrderItem> itemList, AddressInfo addr, String riderName, String riderPhone) {
        return toView(itemList, addr, "", 0L, riderName, riderPhone, "");
    }

    public OrderView toView(List<OrderItem> itemList, AddressInfo addr, String payDeadline, long payDeadlineEpochMs,
                            String riderName, String riderPhone, String readyTime) {
        return new OrderView(id, orderNo, userId, storeId, storeName, status, itemList, addr,
                goodsAmount, deliveryFee, discount, payAmount, remark, reviewed, escrowStatus,
                createTime, payTime, acceptTime, deliverTime, completeTime, expectTime, couponId,
                payDeadline, payDeadlineEpochMs, riderName, riderPhone, readyTime);
    }
}
