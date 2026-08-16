# 简单外卖鸿蒙App完整版 Spec

## Why
本项目是一个鸿蒙（HarmonyOS NEXT / ArkTS）外卖毕设项目，目标对标美团外卖，宗旨是便捷学生点外卖。当前已具备基础"轮子"（常量、模型、Mock数据、AppStorage状态管理、登录页、首页4Tab、商户中心），但缺少完整业务闭环所需的核心页面与功能。需要在此基础上"造车"——采用鸿蒙最新技术栈（状态管理V2、Navigation路由、网络层、持久化、懒加载、地图定位）补全用户端与商户端的完整功能链路，形成技术先进、可演示的毕设作品。

## 技术选型（基于2026鸿蒙最新实践）
本spec结合 HarmonyOS NEXT (API 12+) 最新技术，采用以下技术栈：

| 领域 | 技术方案 | 说明 |
|------|---------|------|
| 状态管理 | `@ObservedV2` + `@Trace` + `PersistenceV2` | V2状态管理支持深度观测与持久化，解决V1多视图数据不同步痛点；PersistenceV2让登录态/购物车/订单在App重启后仍保留 |
| 路由导航 | `Navigation` + `NavPathStack` | API 12+主推方案，替代旧router，支持栈隔离、动效、多端部署；首页主框架保留Tabs，二级页面用NavPathStack管理 |
| 网络请求 | `@ohos/axios`（基于axios v1.3.4适配） | 封装统一网络层，当前对接Mock数据，结构上预留真实API切换能力；需在module.json5配置网络权限 |
| 本地持久化 | `@ohos.data.preferences` + `@ohos.data.relationalStore` | preferences存轻量配置（搜索历史、用户偏好）；relationalStore(SQLite)存结构化数据（订单、地址、收藏） |
| 列表性能 | `LazyForEach` + `cachedCount` | 店铺列表、商品列表、订单列表等长列表按需加载，降低内存占用 |
| 下拉刷新 | `Refresh` 组件 | 首页店铺列表、订单列表支持下拉刷新 |
| 地图定位 | `@kit.MapKit` + `@kit.LocationKit`（可选增强） | 地址选点页接入地图组件，配送跟踪展示骑手位置；作为高阶增强功能 |
| UI组件 | ArkUI声明式 + 自定义组件 | 抽取通用组件（EmptyState、PriceText、RatingStars、Dialog、Timeline） |

## What Changes

### 阶段一：基础轮子加固与现代技术接入（Foundation）
- 数据模型扩展：在 `Models.ets` 新增 Review、Favorite、DeliveryStep、StoreCategory 模型
- 状态管理升级：在 `AppStorageManager.ets` 新增收藏/评价/商户订单流转/统计方法；引入 `PersistenceV2` 持久化关键数据（登录态、购物车、订单列表、收藏列表），App重启后数据不丢失
- 网络层搭建：新增 `service/HttpClient.ets`，基于 `@ohos/axios` 封装统一请求方法（GET/POST），当前对接MockDataService，结构上支持切换真实后端
- 本地存储：新增 `service/PreferencesHelper.ets`（基于preferences存搜索历史）与 `service/LocalDbHelper.ets`（基于relationalStore存订单/地址，可选）
- 通用组件：创建 `components/` 目录，实现 EmptyState、PriceText、RatingStars、Dialog、ConfirmDialog、OrderStatusTimeline
- 路由注册：在 `main_pages.json` 注册所有新页面（仅 `src` 字段，遵循项目约束）

### 阶段二：用户端核心链路（Customer Flow）
- **搜索页（SearchPage）**：热门词、历史搜索（preferences持久化）、店铺/商品搜索结果（LazyForEach懒加载）
- **地址管理页（AddressListPage）**：地址列表、新增/编辑/删除、设置默认；可选接入MapKit地图选点
- **结算页（CheckoutPage）**：选择地址、选择优惠券、备注、配送费/优惠计算、模拟支付、生成订单
- **订单详情页（OrderDetailPage）**：订单信息、商品明细、地址、状态时间轴、订单操作（取消/确认收货/再来一单/评价）
- **订单跟踪**：配送状态进度条（已接单→制作中→配送中→已完成）；可选接入LocationKit展示骑手位置
- **优惠券中心（CouponCenterPage）**：可用/不可用/已用分类、领券、选择优惠券
- **收藏页（FavoriteListPage）**：收藏/取消收藏店铺，收藏列表（PersistenceV2持久化）
- **评价页（ReviewPage）**：订单评价（评分+文字+标签），店铺评价列表
- **个人信息编辑页（ProfileEditPage）**：修改昵称、头像、手机号
- **设置页（SettingsPage）**：清除缓存、退出登录、关于我们

### 阶段三：商户端核心链路（Merchant Flow）
- **商户订单管理（MerchantOrdersPage）**：订单列表按状态Tab（待接单/制作中/配送中/已完成）、接单、出餐、配送状态流转
- **商户收入统计（MerchantStatsPage）**：今日/本周/月收入、订单数、数据卡片展示
- **店铺信息编辑**：修改店铺名称、公告、配送费、起送价、营业状态
- **商品管理增强**：编辑商品、上下架切换、改价

### 阶段四：体验优化与集成（Polish）
- 首页搜索栏联动搜索页；个人中心菜单项跳转对应页面
- 店铺详情页加入收藏按钮、评价入口、商品分类筛选
- 列表页接入 `Refresh` 下拉刷新与 `LazyForEach` 懒加载
- 空状态、加载态统一处理（EmptyState组件）
- 结算链路打通：店铺详情"去结算"跳转结算页（替代当前直接下单）
- **BREAKING**：`main_pages.json` 注册多个新页面（仅 `src` 字段）

## Impact
- Affected specs: 无（项目首次建立完整spec）
- Affected code:
  - `entry/src/main/ets/common/Constants.ets` — 新增评价标签、订单时间轴映射、API端点常量
  - `entry/src/main/ets/model/Models.ets` — 新增 Review、Favorite、DeliveryStep、StoreCategory 模型
  - `entry/src/main/ets/service/MockDataService.ets` — 补充评价、收藏Mock数据
  - `entry/src/main/ets/service/AppStorageManager.ets` — 新增收藏、评价、商户订单流转、统计、用户信息更新方法；接入PersistenceV2
  - `entry/src/main/ets/service/HttpClient.ets`（新增）— @ohos/axios封装网络层
  - `entry/src/main/ets/service/PreferencesHelper.ets`（新增）— preferences存储搜索历史
  - `entry/src/main/ets/components/`（新增目录）— 通用UI组件
  - `entry/src/main/ets/pages/`（新增多个页面）— SearchPage、AddressListPage、CheckoutPage、OrderDetailPage、CouponCenterPage、FavoriteListPage、ReviewPage、ProfileEditPage、SettingsPage、MerchantOrdersPage、MerchantStatsPage
  - `entry/src/main/ets/pages/Index.ets` — 联动搜索、收藏、订单详情跳转、下拉刷新
  - `entry/src/main/resources/base/profile/main_pages.json` — 注册新页面
  - `entry/src/main/module.json5` — 新增网络权限（ohos.permission.INTERNET）、定位权限（可选）
  - `oh-package.json5` — 新增 `@ohos/axios` 依赖

## ADDED Requirements

### Requirement: 状态管理V2与持久化
系统 SHALL 使用 PersistenceV2 持久化登录状态、购物车、订单列表、收藏列表，确保App重启后数据不丢失；搜索历史 SHALL 使用 preferences 存储。

#### Scenario: App重启数据保留
- **WHEN** 用户关闭App后重新打开
- **THEN** 登录状态、购物车商品、历史订单、收藏列表均保留

### Requirement: 网络请求层
系统 SHALL 基于 @ohos/axios 封装统一网络请求层，当前对接本地Mock数据，结构上支持切换真实后端API。

#### Scenario: 统一请求封装
- **WHEN** 页面调用数据获取方法
- **THEN** 通过HttpClient统一发起请求（当前返回Mock数据），支持后续切换真实API

### Requirement: 搜索功能
系统 SHALL 提供搜索页，支持按店铺名/商品名搜索，展示热门词与搜索历史（preferences持久化），结果列表使用LazyForEach懒加载。

#### Scenario: 搜索店铺
- **WHEN** 用户输入关键词并确认
- **THEN** 展示匹配的店铺列表，点击进入店铺详情

#### Scenario: 历史搜索持久化
- **WHEN** 用户搜索某关键词后关闭App再打开搜索页
- **THEN** 该关键词出现在历史搜索中

### Requirement: 地址管理
系统 SHALL 提供地址管理页，支持新增、编辑、删除收货地址，并设置默认地址；可选接入MapKit地图选点。

#### Scenario: 新增地址
- **WHEN** 用户填写姓名、电话、地址、门牌号并保存
- **THEN** 地址加入列表，若设为默认则取消其他默认

#### Scenario: 删除地址
- **WHEN** 用户删除某地址
- **THEN** 该地址从列表移除，若是默认地址则自动将第一条设为默认

### Requirement: 结算下单
系统 SHALL 提供结算页，展示收货地址、商品明细、配送费、优惠金额、实付金额，支持选择优惠券与备注，确认后生成订单。

#### Scenario: 使用优惠券
- **WHEN** 用户选择满足门槛的优惠券
- **THEN** 实付金额 = 商品总价 + 配送费 - 优惠金额，优惠金额正确显示

#### Scenario: 下单成功
- **WHEN** 用户点击提交订单
- **THEN** 生成订单（状态为待接单），清空对应店铺购物车，跳转订单详情页

### Requirement: 订单详情与跟踪
系统 SHALL 提供订单详情页，展示订单全部信息及状态时间轴（OrderStatusTimeline组件），支持对应状态的操作按钮。

#### Scenario: 查看订单详情
- **WHEN** 用户从订单列表点击某订单
- **THEN** 展示店铺、商品明细、地址、金额、状态时间轴、操作按钮

#### Scenario: 取消订单
- **WHEN** 订单为待接单状态，用户点击取消
- **THEN** 订单状态变为已取消，记录取消时间

### Requirement: 优惠券中心
系统 SHALL 提供优惠券中心，按可用/不可用/已用分类展示，支持领券。

#### Scenario: 领取优惠券
- **WHEN** 用户在领券中心点击领取
- **THEN** 优惠券加入用户的优惠券列表

### Requirement: 收藏功能
系统 SHALL 支持收藏/取消收藏店铺（PersistenceV2持久化），并在个人中心提供收藏列表页。

#### Scenario: 收藏店铺持久化
- **WHEN** 用户收藏店铺后重启App
- **THEN** 该店铺仍在收藏列表中

### Requirement: 评价系统
系统 SHALL 支持对已完成订单进行评价（评分+文字+标签），并在店铺详情展示评价列表。

#### Scenario: 提交评价
- **WHEN** 用户在已完成订单点击评价，填写评分与文字后提交
- **THEN** 评价保存到店铺评价列表，订单标记为已评价

### Requirement: 个人信息编辑
系统 SHALL 提供个人信息编辑页，支持修改昵称、手机号。

#### Scenario: 修改昵称
- **WHEN** 用户修改昵称并保存
- **THEN** 用户信息更新，个人中心展示新昵称

### Requirement: 设置页
系统 SHALL 提供设置页，包含清除缓存、退出登录、关于我们入口。

#### Scenario: 退出登录
- **WHEN** 用户点击退出登录
- **THEN** 清除登录状态与购物车，返回首页未登录态

### Requirement: 商户订单管理
系统 SHALL 提供商户订单管理页，按状态分类展示订单，支持接单、出餐、标记配送、完成的状态流转。

#### Scenario: 商户接单
- **WHEN** 商户对待接单订单点击接单
- **THEN** 订单状态变为制作中，记录操作时间

#### Scenario: 商户完成订单
- **WHEN** 商户对配送中订单点击确认送达
- **THEN** 订单状态变为已完成，记录完成时间

### Requirement: 商户收入统计
系统 SHALL 提供商户收入统计页，展示今日订单数、今日收入、本周/月汇总。

#### Scenario: 查看今日收入
- **WHEN** 商户进入收入统计页
- **THEN** 展示今日已完成订单数与收入总额

### Requirement: 商户店铺信息编辑
系统 SHALL 允许商户编辑自己店铺的基本信息（名称、公告、配送费、起送价、营业状态）。

#### Scenario: 修改配送费
- **WHEN** 商户编辑店铺配送费并保存
- **THEN** 店铺信息更新，用户端看到新的配送费

### Requirement: 商户商品管理增强
系统 SHALL 允许商户编辑商品信息（价格、描述、上下架状态）。

#### Scenario: 商品下架
- **WHEN** 商户将商品切换为下架
- **THEN** 该商品在用户端店铺详情中不再展示

### Requirement: 列表性能优化
系统 SHALL 在店铺列表、商品列表、订单列表等长列表场景使用 LazyForEach + cachedCount 按需加载，首页与订单列表 SHALL 支持下拉刷新。

#### Scenario: 长列表流畅滚动
- **WHEN** 店铺/订单数据量较大时
- **THEN** 列表滚动流畅，内存占用低（LazyForEach按需创建/销毁组件）

## MODIFIED Requirements

### Requirement: 首页导航联动
首页顶部搜索栏点击后 SHALL 跳转到独立搜索页；个人中心各菜单项 SHALL 跳转到对应功能页；订单列表点击订单 SHALL 跳转到订单详情页。

### Requirement: 店铺详情增强
店铺详情页 SHALL 增加收藏按钮、评价入口与评价列表展示；商品分类Tab SHALL 支持按分类筛选商品。

## REMOVED Requirements
无（不移除现有功能，仅扩展）

