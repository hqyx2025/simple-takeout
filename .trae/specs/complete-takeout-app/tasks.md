# Tasks

> **Git 规范**：每完成一个 SubTask 必须提交并推送到 Gitee（`https://gitee.com/pengzhiqiang87/simple-takeout.git`）。Commit Message 格式：`<type>(<scope>): <描述>`。详见「开发须知.md」第零章。

## 阶段一：基础轮子加固与现代技术接入（Foundation）
- [ ] Task 1: 扩展数据模型与常量
  - [ ] SubTask 1.1: 在 `Models.ets` 新增 Review（评价）、Favorite（收藏）、DeliveryStep（配送时间轴）、StoreCategory（店铺内商品分类）模型
  - [ ] SubTask 1.2: 在 `Constants.ets` 新增评价标签常量、订单状态时间轴映射、API端点常量
  - [ ] SubTask 1.3: 在 `MockDataService.ets` 补充默认评价数据、收藏数据、配送轨迹数据
- [ ] Task 2: 状态管理升级与持久化
  - [ ] SubTask 2.1: 在 `AppStorageManager.ets` 新增收藏增删查方法（toggleFavorite/getFavorites/isFavorited）
  - [ ] SubTask 2.2: 新增评价方法（addReview/getStoreReviews）
  - [ ] SubTask 2.3: 新增商户订单流转方法（merchantAcceptOrder/merchantStartDelivery/merchantCompleteOrder）
  - [ ] SubTask 2.4: 新增商户收入统计方法（getMerchantTodayStats/getMerchantRangeStats）
  - [ ] SubTask 2.5: 新增用户信息更新方法（updateUserProfile）
  - [ ] SubTask 2.6: 引入 PersistenceV2 持久化登录态、购物车、订单列表、收藏列表（App重启数据不丢失）
- [ ] Task 3: 网络层与本地存储搭建
  - [ ] SubTask 3.1: 安装 `@ohos/axios` 依赖（ohpm install @ohos/axios），在 `oh-package.json5` 添加依赖
  - [ ] SubTask 3.2: 创建 `service/HttpClient.ets`，封装统一GET/POST请求方法，当前对接MockDataService，结构支持切换真实API
  - [ ] SubTask 3.3: 在 `module.json5` 配置网络权限（ohos.permission.INTERNET）
  - [ ] SubTask 3.4: 创建 `service/PreferencesHelper.ets`，基于 @ohos.data.preferences 实现搜索历史存储
- [ ] Task 4: 抽取通用UI组件
  - [ ] SubTask 4.1: 创建 `components/` 目录，实现 EmptyState（空状态）、PriceText（价格）、RatingStars（评分星星）组件
  - [ ] SubTask 4.2: 实现 Dialog（通用弹窗）、ConfirmDialog 组件
  - [ ] SubTask 4.3: 实现 OrderStatusTimeline（订单状态时间轴）组件

## 阶段二：用户端核心链路（Customer Flow）
- [ ] Task 5: 搜索页（SearchPage）
  - [ ] SubTask 5.1: 创建 `pages/SearchPage.ets`，实现搜索栏、热门词、历史搜索（接入PreferencesHelper）
  - [ ] SubTask 5.2: 实现搜索结果列表（店铺/商品），使用 LazyForEach 懒加载，点击跳转店铺详情
  - [ ] SubTask 5.3: 首页搜索栏点击跳转到搜索页
- [ ] Task 6: 地址管理页（AddressListPage）
  - [ ] SubTask 6.1: 创建 `pages/AddressListPage.ets`，展示地址列表
  - [ ] SubTask 6.2: 实现新增/编辑地址表单弹窗
  - [ ] SubTask 6.3: 实现删除、设置默认地址
  - [ ] SubTask 6.4: （可选增强）接入 @kit.MapKit 地图选点
- [ ] Task 7: 结算页（CheckoutPage）
  - [ ] SubTask 7.1: 创建 `pages/CheckoutPage.ets`，展示地址、商品明细、金额计算
  - [ ] SubTask 7.2: 实现优惠券选择入口与回传
  - [ ] SubTask 7.3: 实现备注输入与提交订单，成功后跳转订单详情
- [ ] Task 8: 订单详情页（OrderDetailPage）
  - [ ] SubTask 8.1: 创建 `pages/OrderDetailPage.ets`，展示订单完整信息
  - [ ] SubTask 8.2: 实现订单状态时间轴（使用OrderStatusTimeline组件）
  - [ ] SubTask 8.3: 实现操作按钮（取消/确认收货/再来一单/去评价）
- [ ] Task 9: 优惠券中心（CouponCenterPage）
  - [ ] SubTask 9.1: 创建 `pages/CouponCenterPage.ets`，分类展示优惠券
  - [ ] SubTask 9.2: 实现领券功能
- [ ] Task 10: 收藏页（FavoriteListPage）
  - [ ] SubTask 10.1: 创建 `pages/FavoriteListPage.ets`，展示收藏店铺列表
  - [ ] SubTask 10.2: 实现取消收藏与点击跳转店铺详情
- [ ] Task 11: 评价页（ReviewPage）
  - [ ] SubTask 11.1: 创建 `pages/ReviewPage.ets`，实现评分、文字、标签选择
  - [ ] SubTask 11.2: 提交评价并更新订单已评价状态
  - [ ] SubTask 11.3: 在店铺详情页增加评价列表展示
- [ ] Task 12: 个人信息编辑页（ProfileEditPage）
  - [ ] SubTask 12.1: 创建 `pages/ProfileEditPage.ets`，修改昵称、手机号
- [ ] Task 13: 设置页（SettingsPage）
  - [ ] SubTask 13.1: 创建 `pages/SettingsPage.ets`，包含清除缓存、退出登录、关于我们

## 阶段三：商户端核心链路（Merchant Flow）
- [ ] Task 14: 商户订单管理页（MerchantOrdersPage）
  - [ ] SubTask 14.1: 创建 `pages/MerchantOrdersPage.ets`，按状态Tab展示订单
  - [ ] SubTask 14.2: 实现接单、出餐、配送、完成状态流转
- [ ] Task 15: 商户收入统计页（MerchantStatsPage）
  - [ ] SubTask 15.1: 创建 `pages/MerchantStatsPage.ets`，展示今日/本周/月数据
  - [ ] SubTask 15.2: 实现简单数据卡片展示
- [ ] Task 16: 商户店铺信息编辑
  - [ ] SubTask 16.1: 在 `MerchantCenterPage.ets` 增加店铺信息编辑入口与表单
- [ ] Task 17: 商户商品管理增强
  - [ ] SubTask 17.1: 在 `MerchantCenterPage.ets` 商品项增加编辑（价格/描述）与上下架切换

## 阶段四：体验优化与集成（Polish & Integration）
- [ ] Task 18: 路由与导航集成
  - [ ] SubTask 18.1: 在 `main_pages.json` 注册所有新页面（仅 `src` 字段）
  - [ ] SubTask 18.2: 个人中心菜单项接入对应页面跳转
  - [ ] SubTask 18.3: 订单列表点击跳转订单详情
- [ ] Task 19: 店铺详情增强
  - [ ] SubTask 19.1: 店铺详情增加收藏按钮（收藏/已收藏状态切换）
  - [ ] SubTask 19.2: 店铺详情增加评价入口与评价列表
  - [ ] SubTask 19.3: 商品分类Tab支持按分类筛选
- [ ] Task 20: 列表性能与刷新
  - [ ] SubTask 20.1: 首页店铺列表接入 LazyForEach + Refresh 下拉刷新
  - [ ] SubTask 20.2: 订单列表接入 LazyForEach + Refresh 下拉刷新
  - [ ] SubTask 20.3: 各列表页空数据时展示 EmptyState 组件
- [ ] Task 21: 结算链路打通
  - [ ] SubTask 21.1: 店铺详情"去结算"按钮跳转到结算页（替代当前直接下单）
  - [ ] SubTask 21.2: 结算页与购物车数据打通

# Task Dependencies
- Task 5-21 依赖 Task 1-4（模型/服务/网络层/组件基础）
- Task 5（搜索页）依赖 Task 3.4（PreferencesHelper）
- Task 7（结算页）依赖 Task 6（地址）与 Task 9（优惠券）
- Task 8（订单详情）依赖 Task 4.3（时间轴组件）
- Task 14（商户订单）依赖 Task 2.3（订单流转方法）
- Task 15（收入统计）依赖 Task 2.4（统计方法）
- Task 18-21 可与对应功能页并行开发后统一集成
