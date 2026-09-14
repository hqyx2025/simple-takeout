package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.common.BizException;
import com.example.takeout.model.Order;
import com.example.takeout.model.Rider;
import com.example.takeout.service.OrderService;
import com.example.takeout.service.RiderService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 骑手端接口（四端改造）。所有接口要求 role=3（RIDER）。
 * 配送流程：商家出餐 → 抢单 → 取餐(2→3) → 送达(3→4)。
 */
@RestController
@RequestMapping("/api/rider")
public class RiderController {

    private final RiderService riderService;
    private final OrderService orderService;

    public RiderController(RiderService riderService, OrderService orderService) {
        this.riderService = riderService;
        this.orderService = orderService;
    }

    @GetMapping("/profile")
    public ApiResponse<Rider> profile(@RequestAttribute("userId") long userId,
                                      @RequestAttribute("role") int role) {
        requireRider(role);
        return ApiResponse.ok(riderService.profile(userId));
    }

    @PutMapping("/status")
    public ApiResponse<Rider> setStatus(@RequestAttribute("userId") long userId,
                                        @RequestAttribute("role") int role,
                                        @RequestBody RiderStatusRequest req) {
        requireRider(role);
        return ApiResponse.ok(riderService.setOnline(userId, req.online()));
    }

    /** 可抢订单池（已出餐、未分配骑手）。 */
    @GetMapping("/orders/pool")
    public ApiResponse<List<Order.OrderView>> pool(@RequestAttribute("userId") long userId,
                                                   @RequestAttribute("role") int role) {
        requireRider(role);
        riderService.profile(userId);
        return ApiResponse.ok(orderService.riderPool());
    }

    /** 我的配送单。 */
    @GetMapping("/orders")
    public ApiResponse<List<Order.OrderView>> myOrders(@RequestAttribute("userId") long userId,
                                                       @RequestAttribute("role") int role) {
        requireRider(role);
        return ApiResponse.ok(orderService.riderOrders(riderService.profile(userId).id()));
    }

    @PostMapping("/orders/{id}/grab")
    public ApiResponse<Order.OrderView> grab(@RequestAttribute("userId") long userId,
                                             @RequestAttribute("role") int role,
                                             @PathVariable long id) {
        requireRider(role);
        return ApiResponse.ok(orderService.riderGrab(requireOnlineRider(userId).id(), id));
    }

    @PutMapping("/orders/{id}/pickup")
    public ApiResponse<Order.OrderView> pickup(@RequestAttribute("userId") long userId,
                                               @RequestAttribute("role") int role,
                                               @PathVariable long id) {
        requireRider(role);
        return ApiResponse.ok(orderService.riderPickup(requireOnlineRider(userId).id(), id));
    }

    @PutMapping("/orders/{id}/deliver")
    public ApiResponse<Order.OrderView> deliver(@RequestAttribute("userId") long userId,
                                                @RequestAttribute("role") int role,
                                                @PathVariable long id) {
        requireRider(role);
        Rider rider = requireOnlineRider(userId);
        // 单量与配送收入已由 OrderService.riderDeliver 在同一事务内累加，
        // 此处不得再累加一次（否则重复计单），也不要放在事务外（失败即永久少账）
        return ApiResponse.ok(orderService.riderDeliver(rider.id(), id));
    }

    public record RiderStatusRequest(int online) {
    }

    /** 抢单/取餐/送达前必须在线且未被平台停用，避免离线/停用账号接单造成配送中断。 */
    private Rider requireOnlineRider(long userId) {
        Rider rider = riderService.profile(userId);
        if (rider.status() != 1) {
            throw new BizException(403, "骑手账号已停用，请联系平台管理员");
        }
        if (rider.online() != 1) {
            throw new BizException("请先上线后再接单");
        }
        return rider;
    }

    private void requireRider(int role) {
        if (role != 3) {
            throw new BizException(403, "仅骑手可以执行该操作");
        }
    }
}
