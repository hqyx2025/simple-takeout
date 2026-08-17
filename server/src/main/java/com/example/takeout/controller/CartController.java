package com.example.takeout.controller;

import com.example.takeout.common.ApiResponse;
import com.example.takeout.model.CartItemView;
import com.example.takeout.service.CartService;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/cart")
public class CartController {

    private final CartService service;

    public CartController(CartService service) {
        this.service = service;
    }

    @GetMapping
    public ApiResponse<List<CartItemView>> list(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(service.list(userId));
    }

    @PostMapping("/items")
    public ApiResponse<List<CartItemView>> add(@RequestAttribute("userId") long userId,
                                               @RequestBody CartItemRequest req) {
        return ApiResponse.ok(service.add(userId, req.goodsId(), req.quantity()));
    }

    @PutMapping("/items/{goodsId}")
    public ApiResponse<List<CartItemView>> setQuantity(@RequestAttribute("userId") long userId,
                                                       @PathVariable long goodsId,
                                                       @RequestBody QuantityRequest req) {
        return ApiResponse.ok(service.setQuantity(userId, goodsId, req.quantity()));
    }

    @DeleteMapping("/items/{goodsId}")
    public ApiResponse<List<CartItemView>> deleteOne(@RequestAttribute("userId") long userId,
                                                     @PathVariable long goodsId) {
        return ApiResponse.ok(service.deleteOne(userId, goodsId));
    }

    @DeleteMapping("/items")
    public ApiResponse<List<CartItemView>> deleteBatch(@RequestAttribute("userId") long userId,
                                                       @RequestParam List<Long> goodsIds) {
        return ApiResponse.ok(service.deleteBatch(userId, goodsIds));
    }

    @DeleteMapping
    public ApiResponse<List<CartItemView>> clear(@RequestAttribute("userId") long userId) {
        return ApiResponse.ok(service.clear(userId));
    }

    public record CartItemRequest(long goodsId, int quantity) {
    }

    public record QuantityRequest(int quantity) {
    }
}
