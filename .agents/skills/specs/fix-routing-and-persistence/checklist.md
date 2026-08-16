# Checklist

## 阶段五：关键修复
- [x] 所有 12 个路由页面（SearchPage、AddressListPage、CheckoutPage、OrderDetailPage、CouponCenterPage、FavoriteListPage、ReviewPage、ProfileEditPage、SettingsPage、MerchantOrdersPage、MerchantStatsPage、MerchantCenterPage）均有 `@Entry` 装饰器
- [x] OrderDetailPage 的返回按钮使用 `router.back()` 而非外部回调
- [x] OrderDetailPage "去评价"按钮跳转到 ReviewPage 并传递 currentOrderId
- [x] OrderDetailPage "再来一单"按钮将订单商品加入购物车
- [x] CheckoutPage 提交订单成功后跳转到 OrderDetailPage

## 阶段六：PersistenceV2 持久化
- [x] AppStorageManager.ets / DataPersistence.ets 中持久化关键数据（isLoggedIn、user、cartItems、orderList、favoriteList、addressList、couponList）
- [x] EntryAbility.ets 中初始化持久化数据加载
- [x] App 重启后登录态保留
- [x] App 重启后购物车数据保留
- [x] App 重启后订单列表保留
- [x] App 重启后收藏列表保留

## 阶段七：集成补全
- [x] 从收藏页点击店铺后正确展示店铺详情（onPageShow 监听 currentStoreId 切换发现Tab）
- [x] 从搜索页点击店铺后正确展示店铺详情
- [x] 搜索页返回按钮可用（router.back）
- [x] 所有路由跳转可正常工作（无白屏/报错）
- [x] ArkTS 编译无类型错误（BUILD SUCCESSFUL）

## 阶段八：商户端图表统计
- [x] 商户收入统计页展示近7天收入趋势折线图（Canvas 自绘）
- [x] 商户收入统计页展示今日订单状态分布柱状图（Canvas 自绘）

## 阶段九：配送跟踪可视化
- [x] 订单详情页配送中状态展示骑手位置动画（骑手图标沿轨道移动）
- [x] 配送预估时间展示

## 阶段十：UI 细节打磨
- [x] LoadingIndicator 组件已创建并使用（结算页模拟支付加载态）
- [x] 首页店铺卡片视觉优化完成（RatingStars 评分星星、标签圆角样式）
- [x] 按钮交互反馈优化完成（购物车栏禁用态、结算按钮 enabled 控制）

