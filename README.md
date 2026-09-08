# 简单外卖 · simple-takeout

> HarmonyOS NEXT 外卖点餐 App（毕业设计 / 学习项目，业务对标美团外卖）。
>
> 前端为单 HAP 工程（ArkTS + ArkUI），后端为 Spring Boot 服务端，数据存储于 MySQL，覆盖「用户（点外卖）— 商户（接单出餐）— 平台管理」三类角色。

## 功能特性

### 用户端（CUSTOMER）

- 首页分类导航、推荐/附近店铺列表，店铺与商品搜索
- 店铺详情、商品列表（分类分组、限时特惠）、收藏店铺
- 优惠券领取与下单核销（满减券按商品总价判断门槛）
- 购物车（服务端持久化，按账号隔离）
- 结算下单：选择收货地址 / 优惠券 / 备注，余额支付、下单即扣款
- 订单跟踪（已下单 → 制作中 → 配送中 → 已送达）、确认收货、订单评价
- 收货地址管理（含高德地图定位/选点、默认地址）
- 余额充值、个人资料编辑、联系客服、隐私政策、设置等

### 商户端（MERCHANT）

- 店铺资料维护、平台分类下开店
- 商品管理（增删改、上下架、库存、商户自定义分类、限时特惠标记）
- 订单处理：接单 → 制作 → 配送 → 送达，按状态推进订单
- 营业额统计（仅统计已结算订单，区分待结算/已结算）

### 平台管理端（ADMIN）

- 独立后台：登录后直接进入管理页，不展示用户端首页/定位/购物车
- 平台分类管理、店铺审核（上下架/推荐）、全平台商品与用户管理
- 平台管理员（员工）账号管理
- 全平台订单查看与管理、经营统计（总览 + 订单趋势）
- 已送达订单的退款审批（同意退款 / 拒绝）

### 业务特点

- 金额走平台托管：用户下单扣款后资金 `escrow_status=0` 托管，用户确认收货后才结算给商户
- 幂等与并发安全：退款/结算使用条件更新（`WHERE escrow_status=0`）防重复打款；库存扣减使用乐观锁
- 订单状态机统一用数字状态，前端文案按 `status + escrow_status` 联合判断
- 除注册/登录外全部接口需要 JWT（`Authorization: Bearer`），401 时客户端清登录态回登录页

## 技术栈

| 端 | 技术 | 说明 |
| --- | --- | --- |
| 前端 | HarmonyOS NEXT · ArkTS（严格模式）+ ArkUI | SDK 6.1.1 (API 24)，单 HAP；仅依赖 `@ohos/axios`，无第三方 UI 库 |
| 前端存储 | AppStorage + Preferences | 登录态、购物车展示等本地持久化 |
| 后端 | Spring Boot 3.5.4 · Java 25 | 分层：Controller / Service / DAO；JWT 认证（jjwt）+ 拦截器 |
| 后端数据访问 | JdbcTemplate（购物车为 MyBatis-Plus） | `server/src/main/java/.../dao`、`mapper` |
| 数据库 | MySQL 8.4 | 库名 `takeout`；启动自动执行 `schema.sql`，`DataSeeder` 填充种子数据 |
| 地图 | 高德 Web 端 JS API v2.0 | 通过 ArkUI `Web` 组件内嵌运行，模拟器/真机均可用，无 native 依赖 |
| 测试 | JUnit（后端：越权/幂等/状态机）、ArkTS 单元测试与 ohosTest | `server/src/test`、`entry/src/test`、`entry/src/ohosTest` |

## 仓库结构

```
simple-takeout/
├── AppScope/                 # 应用级配置（bundleName: com.example.jiandanwaimai，应用名：简单外卖）
├── entry/                    # HarmonyOS App 模块（ArkTS 源码、页面、测试）
│   └── src/main/ets/
│       ├── entryability/     # EntryAbility
│       ├── pages/            # 用户端 / 商户端 / 管理端页面
│       ├── components/       # 通用组件（确认弹窗、评分、状态时间轴等）
│       ├── service/          # HttpClient/ApiService、本地持久化、订单计算、定位等
│       ├── common/           # 常量（颜色、API 配置、订单状态文案等）
│       └── model/            # 数据模型
├── server/                   # Spring Boot 后端（端口 9000）
│   └── src/main/
│       ├── java/com/example/takeout/   # controller / service / dao / model / security / config
│       └── resources/                  # application.yml、schema.sql
├── signing/                  # Release 签名配置模板（勿提交真实证书/密码）
├── md/                       # 设计文档（业务流程落地、重构大纲等）
├── .agents/                  # AI 编码助手技能与功能规格
├── AGENTS.md                 # 项目开发记忆（含业务口径与陷阱清单，改代码前必读）
├── build-profile.json5 / oh-package.json5 / hvigorfile.ts / code-linter.json5   # 工程构建配置
└── (hvigor/ 构建工具配置；实际构建在 DevEco Studio 中完成)
```

## 快速开始

### 环境要求

| 依赖 | 版本/说明 |
| --- | --- |
| JDK | 25（后端编译/运行要求） |
| Maven | 3.9+ |
| MySQL | 8.4（本机服务，端口 3306） |
| DevEco Studio | 支持 HarmonyOS NEXT SDK 6.1.1 (API 24) 的版本 |
| 运行设备 | HarmonyOS 模拟器或真机 |

### 1. 初始化数据库

后端启动时会自动执行 `server/src/main/resources/schema.sql` 建表（`spring.sql.init.mode=always`），并通过 `DataSeeder` 在空库写入种子数据，无需手工建库：

- 分类 8 个、店铺约 40 家、商品约 1200 个、5 个测试账号

数据库连接默认 `localhost:3306`、用户名/密码 `root / 123456`，可通过环境变量覆盖：

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `TAKEOUT_DB_USERNAME` | `root` | 数据库用户名 |
| `TAKEOUT_DB_PASSWORD` | `123456` | 数据库密码 |
| `TAKEOUT_JWT_SECRET` | 内置默认值 | JWT 签名密钥（生产环境务必注入） |

### 2. 启动后端

```bash
# 确保 JAVA_HOME 指向 JDK 25，在仓库根目录执行
mvn -f server/pom.xml spring-boot:run
```

- 服务端口：**9000**
- 运行后端测试：`mvn -f server/pom.xml test`

### 3. 运行 App

1. 用 DevEco Studio 打开仓库根目录，等待工程同步完成
2. 连上模拟器或真机直接 Run `entry` 模块（Debug 自动签名）
3. 使用测试账号或注册新账号登录后即可体验

后端地址约定在 `entry/src/main/ets/common/Constants.ets` 的 `API_CONFIG`：

- 模拟器访问宿主机后端：默认 `http://10.0.2.2:9000`，无需修改
- 真机联调：将 `BASE_URL` 改为电脑的局域网 IP（如 `http://192.168.1.100:9000`）
- 发布构建：配置真实 HTTPS 域名后，将 `USE_HTTPS` 置为 `true`

Release 构建需要签名与证书：参考 `signing/release-signing.template.json5` 在本机安全目录填写真实 p12/p7b 路径（真实证书与密码禁止提交到仓库）。

> 地图能力依赖高德 Key（Web 端 JS API 类型）：`Constants.ets` 的 `AMAP_CONFIG` 与 `entry/src/main/resources/rawfile/amap_map.html` 中的 `AMAP_KEY` 需保持一致，Key 含安全密钥时还需填写 `MAP_JS_SECURITY_CODE` / jscode。

### 测试账号（密码均为 `123456`）

| 角色 | 手机号 | 说明 |
| --- | --- | --- |
| 用户（CUSTOMER） | `13800138000` | 新注册用户赠送 20 元体验余额 |
| 商户（MERCHANT） | `13600136000` | 拥有店铺，可在商户端接单 |
| 平台管理员（ADMIN） | `13100131000` | 登录后进入平台管理后台 |

## 接口概览

统一前缀 `/api`，返回统一包装 `ApiResponse`（code/message/data）。除 `POST /api/auth/login`、`POST /api/auth/register` 外均需请求头 `Authorization: Bearer <token>`。

| 分组 | 主要接口 |
| --- | --- |
| 认证 `AuthController` | `POST /api/auth/login`、`POST /api/auth/register`、`GET /api/auth/me`、`PUT /api/auth/me`、`POST /api/auth/recharge` |
| 浏览 `StoreController` | `GET /api/categories`、`/stores`、`/stores/recommended`、`/stores/{id}`、`/stores/{id}/goods`、`/goods/special`、`/stores/{id}/categories`、`GET /api/search` |
| 用户中心 `UserCenterController` | `GET/POST /api/coupons`、`POST /api/coupons/claim`、收藏（`/api/favorites` 查询/状态/切换）、地址（`/api/addresses` 增删改查/设默认）、评价（`/stores/{id}/reviews`、`/goods/{id}/reviews`） |
| 订单 `OrderController` | `POST /api/orders`、`GET /api/orders`、`GET /api/orders/{id}`、`PUT /api/orders/{id}/cancel`、`/confirm`、`POST /api/orders/{id}/review`、`POST /api/orders/{id}/refund` |
| 购物车 `CartController` | `POST /api/cart/items`、`PUT/DELETE /api/cart/items/{goodsId}`、`DELETE /api/cart/items` |
| 商户 `StoreController` | 店铺：`/api/merchant/stores` 增改查、店铺商品增删改查、`PUT /api/merchant/goods/{goodsId}/stock`、商户分类 `/api/merchant/categories` CRUD |
| 商户订单 `OrderController` | `GET /api/merchant/orders`、`PUT /api/merchant/orders/{id}/{action}`（接单/制作/配送/送达）、`GET /api/merchant/stats` |
| 管理端 `AdminController` | 分类/店铺/商品/用户/员工 CRUD 与状态管理（`/api/admin/*`）、`GET /api/admin/statistics/overview`、`/order-trend`、退款审批 `GET /api/admin/refunds`、`POST /api/admin/refunds/{id}/approve`、`/reject` |

## 订单状态与资金托管

订单数字状态（`orders.status`）是唯一权威状态：

| status | 含义 |
| --- | --- |
| 1 | 待接单（下单即扣余额，直接进入该状态） |
| 2 | 制作中 |
| 3 | 配送中 |
| 4 | 已送达：`escrow_status=0` 显示「已送达，待确认收货」，确认后仍为 4、`escrow_status=1` 显示「已完成」 |
| 5 | 已取消 |
| 6 | 退款中（已送达订单发起退款审批后进入） |
| 0 | 待付款（预留，当前支付与下单在同一事务完成） |

托管资金（`orders.escrow_status`）：`0` 托管中 / `1` 已结算（确认收货后结算给商户）/ `2` 已退款。

关键业务规则：

- 下单：扣用户余额、核销优惠券、扣库存（乐观锁），资金进入平台托管，订单为「待接单」
- 取消订单：`status` 1/2/3 可直接取消，即时退款并回滚库存（条件更新防重复退款）
- 确认收货：`status` 保持 4，`escrow_status` 0 → 1，金额结算到商户余额
- 已送达订单退款：`status=4`、`escrow=0` 且未评价时可申请 → 6 → 管理端审批：同意则 `escrow` 0 → 2 并退回用户余额，拒绝则回退 4

## 数据表（MySQL `takeout`）

`users` 用户 / `stores` 店铺 / `goods` 商品 / `orders` 订单（商品与地址为 JSON 快照）/ `coupons` 优惠券 / `reviews` 评价 / `favorites` 收藏 / `addresses` 收货地址 / `categories` 分类（平台/商户）/ `refund_records` 退款申请 / `cart_items` 购物车

## 文档索引

| 文档 | 说明 |
| --- | --- |
| [md/重构大纲提示词.md](md/重构大纲提示词.md) | 唯一权威设计大纲（26 章，含现状/演进标注），改功能前必读 |
| [md/简单外卖业务流程落地.md](md/简单外卖业务流程落地.md) | 角色/流程/接口落地口径（Mermaid 流程图） |
| [md/未完成.txt](md/未完成.txt) | 尚未完成的质量项记录 |
| [AGENTS.md](AGENTS.md) | AI 编码助手项目记忆：技术栈、构建、业务口径、陷阱清单、提交规范 |
| [.agents/skills/specs](.agents/skills/specs) | 功能规格与验收清单（开发/验收依据） |

## 已知未完成项

来自 [md/未完成.txt](md/未完成.txt)：真机 UI 自动化、AppAnalyzer、Release 签名和 HTTPS 联调尚未完成，分别受设备、工具 CLI、证书和 HTTPS 密钥缺失影响。

## 说明

- 本项目为毕业设计/学习用途，支付为余额支付模拟，未接入真实第三方支付/短信/推送。
- 仓库未声明开源许可证，使用前请先与作者确认。
