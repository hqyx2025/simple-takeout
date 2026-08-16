# 路由修复与持久化增强 Spec

## Why
前一阶段开发完成了 21 个核心任务，但验收发现两个关键问题：
1. **路由阻塞**：所有通过 `router.pushUrl` 跳转的页面（SearchPage、AddressListPage、CheckoutPage 等 12 个）均缺少 `@Entry` 装饰器，导致路由跳转无法工作——页面无法被 router 加载。
2. **持久化缺失**：Task 2.6 标记完成但 PersistenceV2 实际未实现，App 重启后登录态、购物车、订单、收藏数据全部丢失。

此外还有若干集成缺口：OrderDetailPage 的回调未接 router、"再来一单"功能未实现等。本 spec 修复这些问题，让项目真正可运行、可演示。

## What Changes

### 阶段五：关键修复（Critical Fixes）
- **BREAKING**：为 12 个路由页面添加 `@Entry` 装饰器（SearchPage、AddressListPage、CheckoutPage、OrderDetailPage、CouponCenterPage、FavoriteListPage、ReviewPage、ProfileEditPage、SettingsPage、MerchantOrdersPage、MerchantStatsPage、MerchantCenterPage）
- 修复 OrderDetailPage：将 `onBack`/`onReview` 回调改为直接使用 `router.back()` 和 `router.pushUrl` 跳转 ReviewPage
- 实现"再来一单"功能：将订单商品重新加入购物车
- 修复 CheckoutPage 提交订单后跳转订单详情（当前仅 `router.back()`）

### 阶段六：PersistenceV2 持久化实现
- 在 `AppStorageManager.ets` 中引入 `PersistenceV2` 持久化关键数据
- 持久化对象：登录态（isLoggedIn）、当前用户（user）、购物车（cartItems）、订单列表（orderList）、收藏列表（favoriteList）、地址列表（addressList）、优惠券列表（couponList）
- 在 `EntryAbility.ets` 的 `onCreate` 中初始化持久化数据加载
- 确保 App 重启后数据不丢失

### 阶段七：集成补全与体验打磨
- OrderDetailPage "去评价"按钮：设置 `currentOrderId` 后跳转 ReviewPage
- OrderDetailPage "再来一单"按钮：将订单商品加入购物车，提示后跳转店铺详情
- CheckoutPage 提交订单成功后：设置 `currentOrder` 并跳转 OrderDetailPage
- 首页"发现"Tab 的店铺详情：从收藏页/搜索页返回时正确展示店铺

### 阶段八：商户端图表统计
- 商户收入统计页增加柱状图/折线图可视化（基于 ArkUI Canvas 自绘）
- 展示近 7 天收入趋势折线图
- 展示今日订单状态分布

### 阶段九：配送跟踪可视化
- 订单详情页配送中状态增加配送进度动画
- 模拟骑手位置移动（基于 OrderStatusTimeline 增强动画效果）
- 配送预估时间展示

### 阶段十：UI 细节打磨
- 统一加载态组件（LoadingIndicator）
- 页面转场动画优化
- 首页店铺卡片视觉优化（评分星星、标签样式）
- 按钮交互反馈（点击态/禁用态）

## Impact
- Affected specs: `complete-takeout-app`（修复其遗留问题）
- Affected code:
  - `entry/src/main/ets/pages/*.ets`（12 个页面添加 @Entry）
  - `entry/src/main/ets/pages/OrderDetailPage.ets`（回调改 router、实现再来一单、配送跟踪动画）
  - `entry/src/main/ets/pages/CheckoutPage.ets`（提交后跳转订单详情）
  - `entry/src/main/ets/pages/MerchantStatsPage.ets`（增加图表可视化）
  - `entry/src/main/ets/service/AppStorageManager.ets`（引入 PersistenceV2）
  - `entry/src/main/ets/entryability/EntryAbility.ets`（初始化持久化）
  - `entry/src/main/ets/components/`（新增 LoadingIndicator 等组件）

## ADDED Requirements

### Requirement: 路由页面 @Entry 装饰
所有通过 `router.pushUrl` 加载的页面 SHALL 使用 `@Entry` 装饰器，否则 router 无法实例化页面。

#### Scenario: 路由跳转可用
- **WHEN** 用户点击个人中心"收货地址"菜单
- **THEN** 通过 `router.pushUrl({ url: 'pages/AddressListPage' })` 成功加载 AddressListPage 页面

### Requirement: 数据持久化
系统 SHALL 使用 PersistenceV2 持久化登录态、用户信息、购物车、订单列表、收藏列表、地址列表、优惠券列表，确保 App 重启后数据不丢失。

#### Scenario: App 重启数据保留
- **WHEN** 用户登录后添加商品到购物车，关闭 App 后重新打开
- **THEN** 登录状态保持，购物车商品保留

### Requirement: 订单详情操作集成
订单详情页的"去评价"按钮 SHALL 跳转到评价页，"再来一单"按钮 SHALL 将订单商品加入购物车。

#### Scenario: 再来一单
- **WHEN** 用户在已完成订单点击"再来一单"
- **THEN** 订单中的商品重新加入购物车，提示"已加入购物车"，返回店铺详情

#### Scenario: 去评价
- **WHEN** 用户在已完成订单点击"去评价"
- **THEN** 设置 `currentOrderId` 后跳转到 ReviewPage

## MODIFIED Requirements

### Requirement: 结算页提交订单跳转
结算页提交订单成功后 SHALL 跳转到订单详情页（而非仅 `router.back()`），展示新生成的订单。

## REMOVED Requirements
无
