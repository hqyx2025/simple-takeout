package com.example.takeout.service;

import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.common.BizException;
import com.example.takeout.model.Order;
import com.example.takeout.model.Store;
import com.example.takeout.model.User;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.*;

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
            super(null, null, null, null, null, null, null);
            this.stores = stores;
        }

        @Override
        public List<Store.StoreView> recommendedStores(double maxDistanceKm, int limit) {
            return stores;
        }
    }

    private static Store.StoreView store(String name, double rating) {
        return new Store.StoreView(1L, name, "", rating, 100, 3.0, 20.0, "30分钟", "1.2km",
                List.of(), "", "地址", null, null, 1, List.of(1), 1L, 1, 1, 0, true);
    }

    private AssistantService service(List<Order> orders, User user, List<Store.StoreView> stores) {
        AssistantConfigService config = mock(AssistantConfigService.class);
        when(config.load()).thenReturn(new AssistantConfigService.Config(false, "", "", ""));
        return new AssistantService(new FakeOrderDao(orders), new FakeUserDao(user), new FakeStoreService(stores),
                config, mock(AssistantAiClient.class));
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
        AssistantService.AssistantReply reply = service(List.of(), user(10.0),
                List.of(store("老王快餐店", 4.8), store("川味小馆", 4.5))).reply(1L, "推荐几家店");
        String answer = reply.answer();

        assertTrue(answer.contains("老王快餐店"), answer);
        assertTrue(answer.contains("川味小馆"), answer);
        assertTrue(answer.contains("4.8"), answer);
        assertEquals("STORE", reply.actions().getFirst().target());
        assertEquals("1", reply.actions().getFirst().value());
        assertEquals("老王快餐店", reply.actions().getFirst().label());
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

    @Test
    void specificOrderOperationsTakePriorityAndRefundDoesNotMeanWallet() {
        AssistantService assistant = service(List.of(), user(99.0), List.of());
        for (String question : List.of("取消订单", "订单怎么退款", "退钱", "怎么支付订单")) {
            AssistantService.AssistantReply reply = assistant.reply(1, question);
            assertEquals("ORDERS", reply.actions().getFirst().target());
            assertFalse(reply.answer().contains("你的余额"), reply.answer());
            assertFalse(reply.answer().contains("还没有订单"), reply.answer());
        }
        assertTrue(assistant.reply(1, "退款").answer().contains("确认收货前申请"));
        assertFalse(assistant.reply(1, "退款").answer().contains("先确认收货"));
    }

    @Test
    void navigationOnlyReturnsKnownPageTargets() {
        AssistantService assistant = service(List.of(), user(0), List.of());
        String[][] destinations = {{"打开订单", "ORDERS"}, {"带我去钱包", "WALLET"},
                {"跳转到收货地址", "ADDRESSES"}, {"打开优惠券", "COUPONS"},
                {"去首页", "HOME"}, {"打开搜索", "SEARCH"}, {"进入收藏", "FAVORITES"},
                {"打开个人资料", "PROFILE"}, {"打开购物车", "CART"}, {"打开设置", "SETTINGS"},
                {"去定位", "LOCATION"}, {"进入客服页面", "SUPPORT"}};
        for (String[] destination : destinations) {
            AssistantService.AssistantReply reply = assistant.reply(1, destination[0]);
            assertEquals(destination[1], reply.actions().getFirst().target());
            assertEquals("LOCAL", reply.source());
        }
        assertTrue(assistant.reply(1, "打开管理员页面").actions().isEmpty());
    }

    @Test
    void generalQuestionUsesConfiguredModelAndFiltersBusinessHistory() {
        AssistantConfigService configService = mock(AssistantConfigService.class);
        AssistantAiClient client = mock(AssistantAiClient.class);
        AssistantConfigService.Config config = new AssistantConfigService.Config(true, "https://provider.example/v1/chat/completions", "model", "secret");
        when(configService.load()).thenReturn(config);
        when(client.complete(eq(config), eq("换一种写法"), anyList())).thenReturn("模型回答");
        AssistantService assistant = new AssistantService(new FakeOrderDao(List.of()), new FakeUserDao(user(20)),
                new FakeStoreService(List.of()), configService, client);
        List<AssistantAiClient.Message> safe = List.of(new AssistantAiClient.Message("user", "写一首诗"),
                new AssistantAiClient.Message("assistant", "春日晴好"));
        List<AssistantAiClient.Message> history = List.of(new AssistantAiClient.Message("user", "余额多少"),
                new AssistantAiClient.Message("assistant", "你的余额是 ¥20.00"), safe.get(0), safe.get(1));

        AssistantService.AssistantReply reply = assistant.reply(1, "换一种写法", history);

        assertEquals("模型回答", reply.answer());
        assertEquals("AI", reply.source());
        assertTrue(reply.actions().isEmpty());
        verify(client).complete(config, "换一种写法", safe);
        when(client.complete(eq(config), eq("推荐一本书"), anyList())).thenReturn("书籍推荐");
        assertEquals("AI", assistant.reply(1, "推荐一本书").source());
        verify(client).complete(config, "推荐一本书", List.of());
        assistant.reply(1, "我的订单");
        assistant.reply(1, "余额多少");
        verifyNoMoreInteractions(client);
    }

    @Test
    void modelAndSecretStorageFailuresFallBackWithoutLeakingDetails() {
        AssistantConfigService config = mock(AssistantConfigService.class);
        when(config.load()).thenThrow(new BizException(503, "private secret"));
        AssistantService assistant = new AssistantService(new FakeOrderDao(List.of()), new FakeUserDao(user(0)),
                new FakeStoreService(List.of()), config, mock(AssistantAiClient.class));
        AssistantService.AssistantReply reply = assistant.reply(1, "帮我写诗");
        assertTrue(reply.answer().contains("暂时不可用"));
        assertFalse(reply.answer().contains("private secret"));
        assertEquals("LOCAL", reply.source());
    }

    @Test
    void refundedTerminalStateDoesNotLookPendingAndMoneyIsExcluded() {
        AssistantService assistant = service(List.of(order(2, 6, 2, 50), order(1, 4, 2, 20)), user(70), List.of());
        String answer = assistant.reply(1, "订单").answer();
        assertTrue(answer.contains("待确认收货 0 笔"));
        assertTrue(answer.contains("已退款"));
        assertTrue(assistant.reply(1, "余额").answer().contains("已支付 ¥0.00"));
    }

    @Test
    void configuredPaymentDeadlineIsUsedInGuidance() {
        AssistantService assistant = service(List.of(), user(0), List.of());
        org.springframework.test.util.ReflectionTestUtils.setField(assistant, "payTimeoutMinutes", 25);
        assertTrue(assistant.reply(1, "怎么支付订单").answer().contains("25 分钟"));
        assertTrue(assistant.reply(1, "我的订单").answer().contains("25 分钟"));
    }
}
