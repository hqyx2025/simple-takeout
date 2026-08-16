# Tasks

> **Git 规范**：每完成一个 SubTask 必须提交并推送到 Gitee。Commit Message 格式：`<type>(<scope>): <描述>`。

## 阶段五：关键修复（Critical Fixes）— 阻塞性问题
- [x] Task 22: 为所有路由页面添加 @Entry 装饰器
  - [x] SubTask 22.1: 为 SearchPage、AddressListPage、CheckoutPage、OrderDetailPage 添加 @Entry
  - [x] SubTask 22.2: 为 CouponCenterPage、FavoriteListPage、ReviewPage、ProfileEditPage、SettingsPage 添加 @Entry
  - [x] SubTask 22.3: 为 MerchantOrdersPage、MerchantStatsPage、MerchantCenterPage 添加 @Entry
- [x] Task 23: 修复 OrderDetailPage 集成
  - [x] SubTask 23.1: 将 onBack 回调改为 router.back()，移除外部回调依赖
  - [x] SubTask 23.2: 将 onReview 回调改为设置 currentOrderId + router.pushUrl 跳转 ReviewPage
  - [x] SubTask 23.3: 实现"再来一单"功能（将订单商品加入购物车）
- [x] Task 24: 修复 CheckoutPage 提交后跳转
  - [x] SubTask 24.1: 提交订单成功后设置 currentOrder 并跳转 OrderDetailPage（替代 router.back）

## 阶段六：PersistenceV2 持久化实现
- [x] Task 25: 实现数据持久化
  - [x] SubTask 25.1: 在 DataPersistence.ets 中用 preferences 持久化 isLoggedIn、user、cartItems、orderList、favoriteList、addressList、couponList
  - [x] SubTask 25.2: 在 EntryAbility.ets onCreate 中调用持久化数据初始化
  - [x] SubTask 25.3: 验证 App 重启后数据保留

## 阶段七：集成补全与体验打磨
- [x] Task 26: 首页发现 Tab 店铺详情返回处理
  - [x] SubTask 26.1: 从收藏页/搜索页点击店铺后，正确切换到发现 Tab 展示店铺详情（Index.ets onPageShow 监听 currentStoreId；SearchPage 返回/店铺点击改为 router 实现）

## 阶段八：商户端图表统计
- [x] Task 27: 商户收入统计图表
  - [x] SubTask 27.1: 在 MerchantStatsPage 增加 Canvas 绘制的近7天收入趋势折线图
  - [x] SubTask 27.2: 增加今日订单状态分布柱状图（AppStorageManager 新增 getMerchantWeekRevenue/getMerchantTodayStatusOrders）

## 阶段九：配送跟踪可视化
- [x] Task 28: 订单配送跟踪动画
  - [x] SubTask 28.1: 订单详情页配送中状态增加骑手位置动画（RiderTracking 组件，骑手图标沿轨道移动）
  - [x] SubTask 28.2: 配送预估时间展示

## 阶段十：UI 细节打磨
- [x] Task 29: UI 体验优化
  - [x] SubTask 29.1: 创建 LoadingIndicator 组件，统一加载态（已接入结算页模拟支付）
  - [x] SubTask 29.2: 首页店铺卡片视觉优化（评分星星改用 RatingStars 组件、标签圆角样式）
  - [x] SubTask 29.3: 按钮交互反馈优化（购物车栏禁用态、结算按钮 enabled 控制）

# Task Dependencies
- Task 23 依赖 Task 22（OrderDetailPage 需先有 @Entry）
- Task 24 依赖 Task 22（CheckoutPage 需先有 @Entry）
- Task 25 独立，可与 Task 22-24 并行
- Task 26 依赖 Task 22
- Task 27-29 依赖 Task 22-26 完成（先修复阻塞性问题再做增强）

