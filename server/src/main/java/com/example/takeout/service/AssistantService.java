package com.example.takeout.service;

import com.example.takeout.dao.OrderDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Order;
import com.example.takeout.model.User;
import com.example.takeout.model.Store;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Locale;

/**
 * 智能助手（规则问答）：不接外部大模型，按关键词命中意图，用库里的真实数据组装回答。
 *
 * <p>设计口径：
 * <ul>
 *   <li>纯只读，不产生任何写操作；不调用外部网络，因此没有密钥/额度依赖。</li>
 *   <li>意图识别用关键词命中，命中不到就走兜底引导；回复里带上真实数字，避免"假智能"感。</li>
 *   <li>用户可见文案与业务口径保持一致（订单状态、托管资金、支付时限等见 AGENTS.md 第 5 节）。</li>
 * </ul>
 */
@Service
public class AssistantService {

    /** 支付时限口径与 takeout.order.pay-timeout-minutes 默认值保持一致。 */
    private static final int PAY_TIMEOUT_MINUTES = 15;

    private final OrderDao orderDao;
    private final UserDao userDao;
    private final StoreService storeService;

    public AssistantService(OrderDao orderDao, UserDao userDao, StoreService storeService) {
        this.orderDao = orderDao;
        this.userDao = userDao;
        this.storeService = storeService;
    }

    /** 助手回答：文本 + 建议追问（前端渲染成可点的快捷问题）。 */
    public record AssistantReply(String answer, List<String> suggestions) {
    }

    public AssistantReply reply(long userId, String question) {
        String q = question == null ? "" : question.trim();
        String lower = q.toLowerCase(Locale.ROOT);
        if (q.isEmpty()) {
            return new AssistantReply("你好，我是简单外卖的智能助手。可以问我「我的订单到哪了」「余额还有多少」「推荐几家店」这类问题。",
                    List.of("我的订单到哪了", "余额还有多少", "推荐几家店"));
        }

        if (hit(lower, "订单", "order", "到哪", "进度", "外卖到", "配送")) {
            return ordersReply(userId);
        }
        if (hit(lower, "余额", "钱包", "钱", "balance", "充值")) {
            return balanceReply(userId);
        }
        if (hit(lower, "推荐", "附近", "推荐店", "吃什么", "好吃", "店铺")) {
            return recommendReply();
        }
        if (hit(lower, "退款", "退钱", "取消订单", "售后")) {
            return refundReply();
        }
        if (hit(lower, "支付", "付款", "付不了", "超时")) {
            return payReply();
        }
        if (hit(lower, "优惠券", "券", "满减")) {
            return new AssistantReply("优惠券可以在「我的 → 优惠券」里领取和使用，结算页会自动列出可用的券；满减门槛按商品总价判断，券后应付为 0 元时不能下单，需要换一张券。",
                    List.of("怎么拿到优惠券", "我的订单到哪了"));
        }
        if (hit(lower, "评价", "差评", "打分")) {
            return new AssistantReply("订单送达并确认收货后就能评价，可以传图；每条订单里同一道菜只能评价一次，评价入口在「我的 → 订单 → 已完成」。",
                    List.of("我的订单到哪了", "退款怎么申请"));
        }
        if (hit(lower, "地址", "定位", "收货", "位置")) {
            return new AssistantReply("收货地址在「我的 → 收货地址」管理，也可以点「去定位」在地图上选点；结算时按店铺逐个校验起送价，只计算该店商品。",
                    List.of("推荐几家店", "我的订单到哪了"));
        }
        if (hit(lower, "你好", "hi", "hello", "在吗", "你是谁")) {
            return new AssistantReply("我是简单外卖的智能助手，能查订单进度、余额、推荐店铺，也能回答退款/优惠券/评价这些常见问题。",
                    List.of("我的订单到哪了", "余额还有多少", "推荐几家店"));
        }

        return new AssistantReply("这个问题我暂时答不上来。你可以换个说法，或者试试下面这些我确定能回答的问题。",
                List.of("我的订单到哪了", "余额还有多少", "推荐几家店", "退款怎么申请"));
    }

    private AssistantReply ordersReply(long userId) {
        List<Order> orders = orderDao.listByUser(userId);
        if (orders.isEmpty()) {
            return new AssistantReply("你还没有订单。去首页挑一家店下单，下单后 15 分钟内完成支付，超时订单会被自动取消。",
                    List.of("推荐几家店", "怎么支付订单"));
        }
        long pendingPay = orders.stream().filter(o -> o.status() == 0).count();
        long inProgress = orders.stream().filter(o -> o.status() == 1 || o.status() == 2 || o.status() == 3).count();
        long waitConfirm = orders.stream().filter(o -> o.status() == 4 && o.escrowStatus() == 0).count();

        StringBuilder sb = new StringBuilder();
        sb.append("你一共有 ").append(orders.size()).append(" 笔订单：");
        sb.append("待付款 ").append(pendingPay).append(" 笔，进行中 ").append(inProgress).append(" 笔，待确认收货 ")
                .append(waitConfirm).append(" 笔。");
        if (pendingPay > 0) {
            sb.append("有 ").append(pendingPay).append(" 笔还没付款，请在 ").append(PAY_TIMEOUT_MINUTES)
                    .append(" 分钟内支付，否则会被自动取消。");
        }

        // 最近一笔的进度：状态文案与前端 getOrderStatusText 口径一致
        Order latest = orders.get(0);
        sb.append("\n最近一笔：").append(latest.storeName()).append("，")
                .append(statusText(latest.status(), latest.escrowStatus())).append("，实付 ¥")
                .append(String.format(Locale.ROOT, "%.2f", latest.payAmount())).append("。");
        return new AssistantReply(sb.toString(), List.of("退款怎么申请", "余额还有多少"));
    }

    private AssistantReply balanceReply(long userId) {
        User user = userDao.findById(userId).orElse(null);
        if (user == null) {
            return new AssistantReply("没能读到你的账户信息，请重新登录后再试。", List.of("我的订单到哪了"));
        }
        List<Order> orders = orderDao.listByUser(userId);
        double spent = orders.stream()
                .filter(o -> o.status() != 0 && o.status() != 5)
                .mapToDouble(Order::payAmount)
                .sum();
        return new AssistantReply(String.format(Locale.ROOT,
                "你的余额是 ¥%.2f，累计已支付 ¥%.2f。余额可以直接用于支付订单，退款也会退回余额；充值入口在「我的 → 测试充值余额」。",
                user.balance(), spent),
                List.of("我的订单到哪了", "推荐几家店"));
    }

    private AssistantReply recommendReply() {
        List<Store.StoreView> stores = storeService.recommendedStores(2, 5);
        if (stores.isEmpty()) {
            return new AssistantReply("暂时没有 2 公里内的推荐店铺。可以先去「去定位」设置收货地址，或者到首页按分类浏览全部店铺。",
                    List.of("怎么设置收货地址", "我的订单到哪了"));
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
        sb.append("。点首页的店铺卡片就能看到菜单。");
        return new AssistantReply(sb.toString(), List.of("满减券怎么用", "我的订单到哪了"));
    }

    private AssistantReply refundReply() {
        return new AssistantReply("退款分两种：待付款订单可以直接取消（还没扣钱，只释放库存和优惠券）；已支付的订单在接单/制作/配送阶段都能直接取消并即时退款。"
                + "已送达的订单需要先确认收货，再按「已送达未确认」申请退款，由平台审批；同意后退款回到你的余额，订单停在「退款中」是正常的终态。",
                List.of("我的订单到哪了", "余额还有多少"));
    }

    private AssistantReply payReply() {
        return new AssistantReply("下单后是「待付款」状态，要在 " + PAY_TIMEOUT_MINUTES
                + " 分钟内完成支付：进「我的 → 订单 → 待付款」点「立即支付」，余额不足会提示，可以先充值。"
                + "超时未付的订单会被平台自动取消并释放库存和优惠券。",
                List.of("余额还有多少", "怎么充值"));
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
                return escrowStatus == 1 ? "已完成" : "已送达，待确认收货";
            case 5:
                return "已取消";
            case 6:
                return "退款中";
            default:
                return "状态未知";
        }
    }
}
