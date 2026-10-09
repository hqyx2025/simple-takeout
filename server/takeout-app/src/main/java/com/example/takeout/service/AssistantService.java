package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Order;
import com.example.takeout.model.User;
import com.example.takeout.model.Store;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Locale;

/** 业务问题使用服务端真实数据；一般问题调用管理员配置的模型，导航由可信规则生成。 */
@Service
public class AssistantService {

    @Value("${takeout.order.pay-timeout-minutes:15}")
    private int payTimeoutMinutes = 15;

    private final OrderDao orderDao;
    private final UserDao userDao;
    private final StoreService storeService;
    private final AssistantConfigService configService;
    private final AssistantAiClient aiClient;

    public AssistantService(OrderDao orderDao, UserDao userDao, StoreService storeService,
                            AssistantConfigService configService, AssistantAiClient aiClient) {
        this.orderDao = orderDao;
        this.userDao = userDao;
        this.storeService = storeService;
        this.configService = configService;
        this.aiClient = aiClient;
    }

    public record Action(String label, String target, String value) {
        public Action(String label, String target) {
            this(label, target, null);
        }
    }

    public record AssistantReply(String answer, List<String> suggestions, List<Action> actions, String source) {
        public AssistantReply(String answer, List<String> suggestions) {
            this(answer, suggestions, List.of(), "LOCAL");
        }
    }

    private static AssistantReply local(String answer, List<String> suggestions, String label, String target) {
        return new AssistantReply(answer, suggestions, List.of(new Action(label, target)), "LOCAL");
    }

    public AssistantReply reply(long userId, String question) {
        return reply(userId, question, List.of());
    }

    public AssistantReply reply(long userId, String question, List<AssistantAiClient.Message> history) {
        AssistantAiClient.validateInput(question, history);
        String q = question == null ? "" : question.trim();
        String lower = q.toLowerCase(Locale.ROOT);
        if (q.isEmpty()) {
            return new AssistantReply("你好，我是简单外卖的智能助手。可以问我「我的订单到哪了」「余额还有多少」「推荐几家店」这类问题。",
                    List.of("我的订单到哪了", "余额还有多少", "推荐几家店"));
        }

        // 先识别具体操作，避免「取消订单」落到订单查询、「退钱」落到钱包。
        if (hit(lower, "退款", "退钱", "取消订单", "取消外卖", "售后")) {
            return refundReply();
        }
        if (hit(lower, "支付", "付款", "付不了", "超时")) {
            return payReply();
        }
        AssistantReply navigation = navigationReply(lower);
        if (navigation != null) {
            return navigation;
        }
        if (hit(lower, "订单", "order", "到哪", "进度", "外卖到", "配送")) {
            return ordersReply(userId);
        }
        if (hit(lower, "余额", "钱包", "balance", "充值")) {
            return balanceReply(userId);
        }
        if (hit(lower, "附近", "推荐店", "吃什么", "好吃", "店铺")
                || (hit(lower, "推荐") && hit(lower, "外卖", "餐", "吃", "店", "美食"))) {
            return recommendReply();
        }
        if (hit(lower, "优惠券", "券", "满减")) {
            return local("优惠券可以在「我的 → 优惠券」里领取和使用，结算页会自动列出可用的券；满减门槛按商品总价判断，券后应付为 0 元时不能下单，需要换一张券。",
                    List.of("怎么拿到优惠券", "我的订单到哪了"), "打开优惠券", "COUPONS");
        }
        if (hit(lower, "评价", "差评", "打分")) {
            return local("订单送达并确认收货后就能评价，可以传图；每条订单里同一道菜只能评价一次，评价入口在「我的 → 订单 → 已完成」。",
                    List.of("我的订单到哪了", "退款怎么申请"), "打开我的订单", "ORDERS");
        }
        if (hit(lower, "地址", "定位", "收货", "位置")) {
            return local("收货地址在「我的 → 收货地址」管理，也可以点「去定位」在地图上选点；结算时按店铺逐个校验起送价，只计算该店商品。",
                    List.of("推荐几家店", "我的订单到哪了"), "管理收货地址", "ADDRESSES");
        }
        if (List.of("你好", "hi", "hello", "在吗", "你是谁").contains(lower)) {
            return new AssistantReply("我是简单外卖的智能助手，能查订单进度、余额、推荐店铺，也能回答退款/优惠券/评价这些常见问题。",
                    List.of("我的订单到哪了", "余额还有多少", "推荐几家店"));
        }

        if (hit(lower, "收藏")) {
            return local("你收藏的店铺可以在「我的 → 我的收藏」查看。", List.of("推荐几家店"), "打开我的收藏", "FAVORITES");
        }
        if (hit(lower, "个人资料", "手机号", "手机号码", "用户名", "账号", "账户", "密码")) {
            return local("个人资料和账号设置请在「我的」页面查看或修改。", List.of(), "打开我的页面", "PROFILE");
        }
        if (hit(lower, "购物车", "cart")) {
            return local("点下面的按钮查看购物车中的商品。", List.of(), "打开购物车", "CART");
        }
        try {
            AssistantConfigService.Config config = configService.load();
            if (config.enabled()) {
                // 兼容旧客户端：业务回复和相关问句不送给外部模型。
                List<AssistantAiClient.Message> safeHistory = history == null ? List.of() : history.stream()
                        .filter(message -> !businessHistory(message.content())).toList();
                return new AssistantReply(aiClient.complete(config, q, safeHistory), List.of(), List.of(), "AI");
            }
        } catch (BizException e) {
            return new AssistantReply("AI 问答服务暂时不可用，请稍后重试。我仍可以查询订单、余额，并带你打开相关页面。",
                    List.of("我的订单到哪了", "余额还有多少", "推荐几家店", "退款怎么申请"));
        }
        return new AssistantReply("管理员尚未开启 AI 问答，这个问题我暂时答不上来。我仍可以查询订单、余额，并带你打开相关页面。",
                List.of("我的订单到哪了", "余额还有多少", "推荐几家店", "退款怎么申请"));
    }

    private static boolean businessHistory(String content) {
        return hit(content.toLowerCase(Locale.ROOT), "订单", "order", "余额", "balance", "钱包", "地址", "收货", "退款",
                "退钱", "支付", "付款", "充值", "优惠券", "手机号", "手机号码", "账号", "账户", "密码", "¥", "￥");
    }

    private AssistantReply navigationReply(String lower) {
        if (!hit(lower, "打开", "跳转", "带我", "前往", "进入", "去", "查看我的")) {
            return null;
        }
        if (hit(lower, "订单", "order")) return local("点下面的按钮查看你的订单。", List.of(), "打开我的订单", "ORDERS");
        if (hit(lower, "钱包", "余额", "充值")) return local("点下面的按钮打开钱包。", List.of(), "打开钱包", "WALLET");
        if (hit(lower, "定位", "地图")) return local("点下面的按钮选择收货位置。", List.of(), "打开定位", "LOCATION");
        if (hit(lower, "地址")) return local("点下面的按钮管理收货地址。", List.of(), "管理收货地址", "ADDRESSES");
        if (hit(lower, "优惠券", "券")) return local("点下面的按钮查看优惠券。", List.of(), "打开优惠券", "COUPONS");
        if (hit(lower, "收藏")) return local("点下面的按钮查看收藏的店铺。", List.of(), "打开我的收藏", "FAVORITES");
        if (hit(lower, "搜索")) return local("点下面的按钮搜索店铺和商品。", List.of(), "打开搜索", "SEARCH");
        if (hit(lower, "首页", "主页")) return local("点下面的按钮回到首页。", List.of(), "回到首页", "HOME");
        if (hit(lower, "设置")) return local("点下面的按钮打开设置。", List.of(), "打开设置", "SETTINGS");
        if (hit(lower, "客服")) return local("点下面的按钮联系客服。", List.of(), "联系客服", "SUPPORT");
        if (hit(lower, "个人", "我的页面", "资料")) return local("点下面的按钮打开我的页面。", List.of(), "打开我的页面", "PROFILE");
        return null;
    }

    private AssistantReply ordersReply(long userId) {
        List<Order> orders = orderDao.listByUser(userId);
        if (orders.isEmpty()) {
            return local("你还没有订单。去首页挑一家店下单，下单后 " + Math.max(payTimeoutMinutes, 1) + " 分钟内完成支付，超时订单会被自动取消。",
                    List.of("推荐几家店", "怎么支付订单"), "去首页挑选店铺", "HOME");
        }
        long pendingPay = orders.stream().filter(o -> o.status() == 0).count();
        long inProgress = orders.stream().filter(o -> o.status() == 1 || o.status() == 2 || o.status() == 3).count();
        long waitConfirm = orders.stream().filter(o -> o.status() == 4 && o.escrowStatus() == 0).count();

        StringBuilder sb = new StringBuilder();
        sb.append("你一共有 ").append(orders.size()).append(" 笔订单：");
        sb.append("待付款 ").append(pendingPay).append(" 笔，进行中 ").append(inProgress).append(" 笔，待确认收货 ")
                .append(waitConfirm).append(" 笔。");
        if (pendingPay > 0) {
            sb.append("有 ").append(pendingPay).append(" 笔还没付款，请在 ").append(Math.max(payTimeoutMinutes, 1))
                    .append(" 分钟内支付，否则会被自动取消。");
        }

        // 最近一笔的进度：状态文案与前端 getOrderStatusText 口径一致
        Order latest = orders.get(0);
        sb.append("\n最近一笔：").append(latest.storeName()).append("，")
                .append(statusText(latest.status(), latest.escrowStatus())).append("，实付 ¥")
                .append(String.format(Locale.ROOT, "%.2f", latest.payAmount())).append("。");
        return local(sb.toString(), List.of("退款怎么申请", "余额还有多少"), "查看我的订单", "ORDERS");
    }

    private AssistantReply balanceReply(long userId) {
        User user = userDao.findById(userId).orElse(null);
        if (user == null) {
            return new AssistantReply("没能读到你的账户信息，请重新登录后再试。", List.of("我的订单到哪了"));
        }
        List<Order> orders = orderDao.listByUser(userId);
        double spent = orders.stream()
                .filter(o -> o.status() != 0 && o.status() != 5 && o.escrowStatus() != 2)
                .mapToDouble(Order::payAmount)
                .sum();
        return local(String.format(Locale.ROOT,
                "你的余额是 ¥%.2f，当前未退款订单已支付 ¥%.2f。余额可以直接用于支付订单，退款也会退回余额；充值入口在钱包页面。",
                user.balance(), spent),
                List.of("我的订单到哪了", "推荐几家店"), "打开钱包", "WALLET");
    }

    private AssistantReply recommendReply() {
        List<Store.StoreView> stores = storeService.recommendedStores(2, 5);
        if (stores.isEmpty()) {
            return local("暂时没有 2 公里内的推荐店铺。可以先去「去定位」设置收货地址，或者到首页按分类浏览全部店铺。",
                    List.of("怎么设置收货地址", "我的订单到哪了"), "浏览首页店铺", "HOME");
        }
        StringBuilder sb = new StringBuilder("按评分给你挑了 ").append(stores.size()).append(" 家店：");
        for (int i = 0; i < stores.size(); i++) {
            Store.StoreView store = stores.get(i);
            if (i > 0) {
                sb.append("；");
            }
            sb.append(store.name()).append("（评分 ").append(store.rating())
                    .append("，配送费 ¥").append(String.format(Locale.ROOT, "%.2f", store.deliveryFee()))
                    .append("）");
        }
        sb.append("。点下面的店铺按钮查看菜单。");
        List<Action> actions = stores.stream().map(store -> new Action(store.name(), "STORE", Long.toString(store.id()))).toList();
        return new AssistantReply(sb.toString(), List.of("满减券怎么用", "我的订单到哪了"), actions, "LOCAL");
    }

    private AssistantReply refundReply() {
        return local("退款分两种：待付款订单可以直接取消（还没扣钱，只释放库存和优惠券）；已支付的订单在待接单/制作/配送阶段可取消并即时退款。"
                + "已送达但未确认收货、未评价的订单可以申请退款，等待平台审批；请在确认收货前申请。审批同意后款项回到余额，订单状态和资金退款状态共同表示退款结果。",
                List.of("我的订单到哪了", "余额还有多少"), "查看订单与退款入口", "ORDERS");
    }

    private AssistantReply payReply() {
        return local("下单后是「待付款」状态，要在 " + Math.max(payTimeoutMinutes, 1)
                + " 分钟内完成支付：进「我的 → 订单 → 待付款」点「立即支付」，余额不足会提示，可以先充值。"
                + "超时未付的订单会被平台自动取消并释放库存和优惠券。",
                List.of("余额还有多少", "怎么充值"), "查看待付款订单", "ORDERS");
    }

    private static boolean hit(String lower, String... keywords) {
        for (String keyword : keywords) {
            if (lower.contains(keyword)) {
                return true;
            }
        }
        return false;
    }

    /** 与前端 getOrderStatusText 保持一致的订单状态文案。 */
    private static String statusText(int status, int escrowStatus) {
        switch (status) {
            case 0:
                return "待付款";
            case 1:
                return "待接单";
            case 2:
                return "制作中";
            case 3:
                return "配送中";
            case 4:
                return escrowStatus == 1 ? "已完成" : escrowStatus == 2 ? "已退款" : "已送达，待确认收货";
            case 5:
                return "已取消";
            case 6:
                return escrowStatus == 2 ? "已退款" : "退款中";
            default:
                return "状态未知";
        }
    }
}
