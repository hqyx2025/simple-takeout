# Checklist

## Git 工作流检查
- [ ] 远程仓库已配置（`git remote -v` 显示 `origin → https://gitee.com/pengzhiqiang87/simple-takeout.git`）
- [ ] 每完成一个 SubTask 都已 commit 并 push 到 Gitee
- [ ] 所有 commit message 遵循 `<type>(<scope>): <描述>` 格式
- [ ] 未提交 `build/` 和 `.preview/` 目录

## 阶段一：基础轮子加固与现代技术接入
- [ ] `Models.ets` 包含 Review、Favorite、DeliveryStep、StoreCategory 模型定义
- [ ] `Constants.ets` 包含评价标签、订单时间轴映射、API端点常量
- [ ] `MockDataService.ets` 提供默认评价、收藏、配送轨迹数据
- [ ] `AppStorageManager.ets` 提供收藏、评价、商户订单流转、统计、用户信息更新方法
- [ ] PersistenceV2 已持久化登录态、购物车、订单列表、收藏列表
- [ ] `@ohos/axios` 已安装并在 `oh-package.json5` 注册依赖
- [ ] `service/HttpClient.ets` 封装统一GET/POST请求方法，对接Mock数据
- [ ] `module.json5` 配置了网络权限（ohos.permission.INTERNET）
- [ ] `service/PreferencesHelper.ets` 实现搜索历史存储（基于preferences）
- [ ] `components/` 目录存在 EmptyState、PriceText、RatingStars、Dialog、ConfirmDialog、OrderStatusTimeline 组件

## 阶段二：用户端核心链路
- [ ] 搜索页可输入关键词展示店铺/商品结果，展示热门词与历史
- [ ] 搜索历史通过 preferences 持久化，App重启后保留
- [ ] 搜索结果列表使用 LazyForEach 懒加载
- [ ] 首页搜索栏点击跳转搜索页
- [ ] 地址管理页可增删改查地址，支持设置默认
- [ ] 结算页正确计算金额（商品+配送费-优惠），支持选优惠券与备注
- [ ] 结算页提交订单后清空购物车并跳转订单详情
- [ ] 订单详情页展示完整订单信息与状态时间轴（OrderStatusTimeline组件）
- [ ] 订单详情页操作按钮按状态正确显示（取消/确认收货/再来一单/评价）
- [ ] 优惠券中心分类展示（可用/不可用/已用），支持领券
- [ ] 收藏页展示收藏店铺，可取消收藏并跳转详情
- [ ] 收藏数据通过 PersistenceV2 持久化，App重启后保留
- [ ] 评价页可评分、写文字、选标签，提交后订单标记已评价
- [ ] 店铺详情页展示评价列表
- [ ] 个人信息编辑页可修改昵称、手机号并保存
- [ ] 设置页包含清除缓存、退出登录、关于我们

## 阶段三：商户端核心链路
- [ ] 商户订单管理页按状态Tab展示订单
- [ ] 商户可接单（待接单→制作中）、出餐（制作中→配送中）、确认送达（配送中→已完成）
- [ ] 商户收入统计页展示今日订单数与收入
- [ ] 商户可编辑店铺信息（名称、公告、配送费、起送价）
- [ ] 商户可编辑商品价格/描述与上下架

## 阶段四：体验优化与集成
- [ ] `main_pages.json` 注册所有新页面（仅 `src` 字段，无 `routerMap`）
- [ ] 个人中心各菜单项可跳转到对应功能页
- [ ] 订单列表点击订单可跳转订单详情页
- [ ] 店铺详情页有收藏按钮，状态正确切换
- [ ] 店铺详情页商品分类Tab可按分类筛选
- [ ] 店铺详情"去结算"跳转结算页（非直接下单）
- [ ] 首页店铺列表接入 LazyForEach + Refresh 下拉刷新
- [ ] 订单列表接入 LazyForEach + Refresh 下拉刷新
- [ ] 各列表页空数据时展示 EmptyState 组件
- [ ] ArkTS 编译无 `arkts-no-untyped-obj-literals` 等类型错误
- [ ] 遵循项目约束（ShadowOptions.offsetY 为 number、LengthMetrics.vp()、main_pages.json 仅 src/window）

