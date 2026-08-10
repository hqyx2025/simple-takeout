package com.example.takeout.model;

import java.util.List;

/**
 * 订单（status 与客户端对齐：0待付款 1待接单 2制作中 3配送中 4已完成 5已取消 6退款中）
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
        String createTime,
        String payTime,
        String acceptTime,
        String deliverTime,
        String completeTime
) {
    /**
     * 订单商品项（对应客户端 CartItem 结构）
     */
    public record OrderItem(
            long goodsId,
            String goodsName,
            double price,
            int quantity,
            String image
    ) {
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
     * 视图模型：items/address 解析为结构体
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
            String createTime,
            String payTime,
            String acceptTime,
            String deliverTime,
            String completeTime
    ) {
    }

    public OrderView toView(List<OrderItem> itemList, AddressInfo addr) {
        return new OrderView(id, orderNo, userId, storeId, storeName, status, itemList, addr,
                goodsAmount, deliveryFee, discount, payAmount, remark, reviewed,
                createTime, payTime, acceptTime, deliverTime, completeTime);
    }
}
