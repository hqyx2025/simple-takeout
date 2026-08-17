# 简单外卖（jiandanwaimai）项目记忆

> 本文件由 Qoder 开发记忆整理移植，供 Codex 等 AI 编码助手读取。内容与仓库现状严格对齐，修改代码前务必阅读。

## 1. 项目概述

- **定位**：HarmonyOS NEXT 外卖 App（毕业设计，对标美团外卖），单 HAP 工程
- **双业务闭环**：用户端（搜索→下单→评价）与商户端（接单→出餐→统计）
- **目录结构**：`server/` 后端模块（Spring Boot）+ `entry/` 前端模块（HarmonyOS ArkTS）
- **核心文档**：`md/重构大纲提示词.md` 是唯一权威设计文档（26 章），含"现状/演进"标注；第 17 节约束：**以仓库现状为准、禁止推倒重来、冲突先列后改**
- **管理端独立后台**：ADMIN 登录后直接进入平台管理页（AdminCenterPage + 分类/店铺/订单/退款审批四个独立页面），任何情况下不展示主页/定位/购物车等 C 端功能

## 2. 技术栈

| 层 | 技术 | 关键点 |
| --- | --- | --- |
| 前端 | HarmonyOS NEXT ArkTS（严格模式）+ ArkUI | SDK 6.1.1(24)，无第三方 UI 依赖，AppStorage + Preferences 持久化 |
| 后端 | Spring Boot 3.5.4 + Java 25 | JWT 认证（`Authorization: Bearer`）、JdbcTemplate（**非 MyBatis-Plus**）、Lombok |
| 数据库 | MySQL 8.4（本机服务名 MySQL84） | 库名 `takeout`，`createDatabaseIfNotExist=true` 自动建库，schema.sql 启动自动执行 |
| 地图 | 高德 Web 端 JS API v2.0 + Web 组件 | 无 native 依赖，模拟器/真机均可运行；**勿用 @amap/amap_lbs_map3d**（仅 arm64，x86_64 模拟器 ABI 不匹配安装失败 9568347） |
| 工具 | Maven、Hutool 可选演进 | 短信/微信支付/支付宝/OSS/Redis 均为**演进项**，未批准不得落地 |

## 3. 构建与运行

- 后端启动：先设 `JAVA_HOME` 指向 JDK 25.0.2，再 `mvn -f server/pom.xml spring-boot:run`（端口 9000，**非 8080**）
- 前端构建：`DEVECO_SDK_HOME` 指向 DevEco SDK 后执行 `hvigorw.bat assembleHap --mode module -p product=default --no-daemon`
- 后端测试：`mvn -f server/pom.xml test`（17 个测试，覆盖越权/幂等/状态机）
- **注意**：PowerShell 5.x 不支持 `&&`，连续命令必须分开执行
- 模拟器访问宿主机后端：`http://10.0.2.2:9000`

## 4. 环境配置

- **MySQL**：`localhost:3306`，root / 123456，库 takeout；凭据走环境变量 `TAKEOUT_DB_USERNAME/TAKEOUT_DB_PASSWORD`（默认 root/123456）
- **JWT**：`TAKEOUT_JWT_SECRET` 环境变量，`expire-hours: 72`；无刷新令牌（每 72 小时重新登录的体验取舍已接受）
- **日志**：按天分文件 `app-YYYY-MM-DD.log`，单文件 2MB 轮转压缩归档（zip）；同时输出控制台 + `filesDir/log/app.log`；密码/JWT/手机号完整值禁止入日志
- **高德 Key**（双 Key 概念）：`AMAP_CONFIG.MAP_JS_KEY`（Web端 JS API 类型，`a0373d4b39b6524b7f80e825339e7a28`，需同步修改 `resources/rawfile/amap_map.html` 中 AMAP_KEY）；2021 年后 Key 需配置安全密钥 jscode

## 5. 核心业务口径（改代码前必读）

- **订单状态机（双轨制）**：数字状态（1 待接单 / 2 制作中 / 3 配送中 / 4 已送达待确认 / 5 已取消；0 待付款、6 退款中为预留）是**唯一权威**；大纲第 6 章字符串状态机（PENDING_ACCEPT 等）是**目标演进状态机**，仅规划参考
- **托管资金 escrow_status**：0 托管中 / 1 已结算 / 2 已退款；确认收货不改变 status（保持 4），只改 escrow 0→1 并给商户加余额；**前端状态文案必须按 status + escrow 联合判断**（status=4 且 escrow=0 显示"已送达，待确认收货"，escrow=1 显示"已完成"）
- **支付**：现状为"余额支付下单即扣款"（下单接口直接扣余额、订单 status=1），无待支付状态；第三方支付/回调/超时任务为演进项
- **取消订单**：status 1/2/3 均可直接取消、**即时退款**（escrow 0→2 条件更新防重复 → 退用户余额 → status=5），无需商家确认；退款审批流程仅用于已送达订单（status=4 且 escrow=0 且未评价可申请 → status=6 → 管理端同意 escrow=2 或拒绝回退 status=4）
- **金额口径**：满减券门槛按**商品总价**判断（非实付）；月销量为"累计下单数"（取消不回滚）；金额统一两位小数
- **幂等**：退款/结算必须条件更新（`WHERE escrow_status=0`），防重复打款/退款；库存扣减用乐观锁（`WHERE stock>=? AND status=1`），取消/退款时 escrow 更新成功后才回滚库存
- **测试账号**：用户 13800138000 / 商户 13600136000 / 管理端 13100131000，密码均 123456；注册用户送 20 元余额
- **接口约定**：除 `/api/auth/login`、`/api/auth/register` 外全部接口需 JWT（含浏览类）；401 时前端清登录态回登录页

## 6. 数据库现状（差异以 22.8 节清单为准）

- 实际表名（复数）：`users` `stores` `goods` `orders` `coupons` `reviews` `favorites` `addresses` `categories` `refund_records`
- 关键现状：goods 有 `stock/version/merchant_category_id`（演进项已落地）；orders 的 items/address 为 **JSON 快照**（无独立明细表）；categories 有 `type`（PLATFORM/MERCHANT）+ `merchant_id`；reviews **无 order_id/reply**（防重靠 orders.reviewed）
- 演进项（未落地，勿实现）：banner/announcement 表、order_item/payment_record/user_coupon/order_status_log 表、address 经纬度、商户配送半径、逻辑删除字段

## 7. 开发规范（ArkTS 严格模式）

- `Stack` 不支持 `justifyContent/alignItems`，用 `alignContent(Alignment.X)`；`Row.alignItems` 用 `VerticalAlign`；`Alignment` 无 `CenterStart`
- **禁止空对象字面量 `{}`**：必须定义显式 class + 静态 `create()` 工厂（满足 arkts-no-untyped-obj-literals）
- **禁止向 `object` 类型参数传字面量**（如 `Web.javaScriptProxy`）：定义显式 interface 并经方法返回实例
- 表单弹窗：每个输入字段加标签（必填/选填）+ 业务示例 placeholder（如"请输入店铺名称，如：老王快餐店"）；顶部说明操作影响
- **渲染禁用 getter 计算属性**：ArkUI 对 getter 求值存在时序问题，会引发渲染崩溃（TypeError: Cannot read property length of undefined）；列表筛选结果应显式存入 `@State` 数组 + 内联 `Array.isArray` 防御
- ForEach 的 item 参数不能用于**嵌套闭包**（onClick 内引用会编译失败），需提取 @Builder 方法传参
- 遵循 `.agents/skills/specs/` 文档作为功能开发与验收依据

## 8. 经验教训（陷阱清单）

- 高德地图 SDK（@amap/amap_lbs_map3d）仅 arm64 → x86_64 模拟器安装失败（9568347），用 Web JS API 方案
- OpenHarmony zlib 正确模块是 `@ohos.zlib`（非 @ohos.file.zlib）；`compressFile` 的 options 必传但字段全可选，可用类型化空对象
- SQLite 相对路径需预先 `Files.createDirectories` 创建父目录（已迁 MySQL，勿回退）
- 优惠券/收藏等业务数据**禁止前端模拟**，服务端返回后必须以后端数据为准；默认分类图标仅作暂无数据占位
- 商户统计只统计已结算订单（status=4 且 escrow=1），区分"待结算"与"已结算营业额"
- 页面包含底部固定购物车或提交栏时，主体必须用 `Scroll`/`List` 承载，并用 `layoutWeight(1)` 分配顶部栏以下的剩余高度；滚动内容保留底部安全区，避免最后的评价、提交按钮被遮挡。
- 独立详情页的结构固定为“顶部导航 + 主体纵向 Scroll/List + 底部操作栏”，不要在父级 `Column` 中让详情组件使用 `height('100%')` 挤压兄弟组件。
- 评价入口不能因暂时不可评价而完全消失：可评价显示“去评价”，未完成订单显示“评价”并提示“完成订单后才能评价”，已评价显示已评价状态。
- 收货地址必须按账号闭环：结算页地址卡片点击进入地址列表，选择已有地址后返回并刷新；定位页确认位置必须调用后端新增地址接口取得真实 `id`，不能只写本地 `id=0`；登录成功或恢复登录态时同步当前账号地址，并优先恢复默认地址。
- 持久化归一化不能把合法的 `addressList` 直接重置为空数组；退出登录清除旧账号缓存后，下一次登录必须从数据库重新恢复地址，避免账号间串地址或反复要求定位。

## 9. 提交规范

- 提交信息格式 `<type>(<scope>): <描述>`，如 `feat(merchant):`、`fix(order):`、`docs:`
- 任务完成后主动 commit + push 到 Gitee（https://gitee.com/pengzhiqiang87/simple-takeout.git，master 分支）
- 只改文档时不得修改业务代码/数据库脚本/配置文件，且不自动提交
