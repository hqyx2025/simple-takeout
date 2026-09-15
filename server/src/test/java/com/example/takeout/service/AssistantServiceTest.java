package com.example.takeout.service;

import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Order;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 智能助手规则问答的意图路由与数据组装（纯单元测试，不起 Spring 上下文）。
 * 注意助手是只读的：这里同时守住"回答里带真实数据"和"命中不到不胡编"两条底线。
 */
class AssistantServiceTest {

    private static Order order(long id, int status, int escrowStatus, double payAmount) {
        return new Order(id, "NO" + id, 1L, 9L, "老王快餐店", status, "[]", "{}",
                20.0, 3.0, 0.0, payAmount, "", 0, escrowStatus,
                "2026-09-15 10:00:00", null, null, null, null, null, 0L);
    }

    private static User user(double balance) {
        return new User(1L, "测试用户", "", "13800138000", "", 0, balance, "2026-01-01 00:00:00");
    }

    /** 手写替身：只实现助手真正用到的读取方法。 */
    private static class FakeOrderDao extends OrderDao {
        private final List<Order> orders;

        FakeOrderDao(List<Order> orders) {
            super(null);
            this.orders = orders;
        }

        @Override
        public List<Order> listByUser(long userId) {
            return orders;
        }
    }

    private static class FakeUserDao extends UserDao {
        private final User user;

        FakeUserDao(User user) {
            super(null);
            this.user = user;
        }

        @Override
        public java.util.Optional<User> findById(long id) {
            return java.util.Optional.ofNullable(user);
        }
    }

    private static class FakeStoreService extends StoreService {
        private final List<Store.StoreView> stores;

        FakeStoreService(List<Store.StoreView> stores) {
            super(null, null, null, null, null, null);
            this.stores = stores;
        }

        @Override
        public List<Store.StoreView> recommendedStores(double maxDistanceKm, int limit) {
            return stores;
        }
    }

    private static Store.StoreView store(String name, double rating) {
        return new Store.StoreView(1L, name, "", rating, 100, 3.0, 20.0, "30分钟", "1.2km",
                List.of(), "", "地址", null, null, 1, List.of(1), 1L, 1, 1);
    }

    private AssistantService service(List<Order> orders, User user, List<Store.StoreView> stores) {
        return new AssistantService(new FakeOrderDao(orders), new FakeUserDao(user), new FakeStoreService(stores));
    }

    @Test
    void orderQuestionReportsRealCountsAndLatestOrder() {
        AssistantService assistant = service(List.of(
                order(4, 4, 0, 42.0),
                order(3, 0, 0, 25.5),
                order(2, 3, 0, 18.0),
                order(1, 4, 1, 30.0)), user(50.0), List.of());

        String answer = assistant.reply(1L, "我的订单到哪了").answer();

        assertTrue(answer.contains("4 笔订单"), answer);
        assertTrue(answer.contains("待付款 1 笔"), answer);
        assertTrue(answer.contains("进行中 1 笔"), answer);
        // status=4 且 escrow=0 才是"待确认收货"；escrow=1 属于已完成，不计入
        assertTrue(answer.contains("待确认收货 1 笔"), answer);
        // 最近一笔（id 最大）的店铺与金额要出现在回答里
        assertTrue(answer.contains("老王快餐店"), answer);
        assertTrue(answer.contains("42.00"), answer);
    }

    @Test
    void orderQuestionOnEmptyHistoryGuidesToOrdering() {
        String answer = service(List.of(), user(0.0), List.of()).reply(1L, "订单").answer();

        assertTrue(answer.contains("还没有订单"), answer);
        assertFalse(answer.contains("0 笔订单"), answer);
    }

    @Test
    void balanceQuestionUsesWalletAmountAndExcludesCancelledSpending() {
        AssistantService assistant = service(List.of(
                order(2, 1, 0, 20.0),
                order(1, 5, 0, 99.0)), user(37.5), List.of());

        String answer = assistant.reply(1L, "余额还有多少").answer();

        assertTrue(answer.contains("37.50"), answer);
        // 已取消订单不计入累计支付
        assertTrue(answer.contains("20.00"), answer);
        assertFalse(answer.contains("119.00"), answer);
    }

    @Test
    void recommendQuestionListsStoresWithRating() {
        String answer = service(List.of(), user(10.0),
                List.of(store("老王快餐店", 4.8), store("川味小馆", 4.5))).reply(1L, "推荐几家店").answer();

        assertTrue(answer.contains("老王快餐店"), answer);
        assertTrue(answer.contains("川味小馆"), answer);
        assertTrue(answer.contains("4.8"), answer);
    }

    @Test
    void recommendQuestionWithoutNearbyStoresExplainsWhy() {
        String answer = service(List.of(), user(10.0), List.of()).reply(1L, "附近有什么好吃的").answer();

        assertTrue(answer.contains("没有 2 公里内的推荐店铺"), answer);
    }

    @Test
    void unknownQuestionFallsBackWithSuggestionsInsteadOfInventing() {
        AssistantService.AssistantReply reply = service(List.of(), user(0.0), List.of())
                .reply(1L, "帮我写一首诗");

        assertTrue(reply.answer().contains("暂时答不上来"), reply.answer());
        assertEquals(4, reply.suggestions().size());
    }

    @Test
    void emptyQuestionGreetsAndSuggests() {
        AssistantService.AssistantReply reply = service(List.of(), user(0.0), List.of()).reply(1L, "   ");

        assertTrue(reply.answer().contains("智能助手"), reply.answer());
        assertEquals(3, reply.suggestions().size());
    }

    @Test
    void refundAndPayAndCouponQuestionsAreRoutedToTheirOwnAnswers() {
        AssistantService assistant = service(List.of(), user(0.0), List.of());

        assertTrue(assistant.reply(1L, "退款怎么申请").answer().contains("退款"), "退款意图未命中");
        assertTrue(assistant.reply(1L, "付不了款怎么办").answer().contains("15 分钟"), "支付意图未命中");
        assertTrue(assistant.reply(1L, "优惠券怎么用").answer().contains("优惠券"), "优惠券意图未命中");
        assertTrue(assistant.reply(1L, "怎么加地址").answer().contains("收货地址"), "地址意图未命中");
    }
}
