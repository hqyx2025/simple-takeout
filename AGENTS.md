# 简单外卖（jiandanwaimai）项目记忆

> 本文件由 Qoder 开发记忆整理移植，供 Codex 等 AI 编码助手读取。内容与仓库现状严格对齐，修改代码前务必阅读。

## 1. 项目概述

- **定位**：HarmonyOS NEXT 外卖 App（毕业设计，对标美团外卖），单 HAP 工程
- **四端闭环**：用户端（搜索→下单→评价）/ 商户端（接单→出餐→统计）/ 骑手端（抢单→取餐→送达）/ 平台管理端（审核→内容→统计）
- **目录结构**：`server/` 后端模块（Spring Boot）+ `entry/` 前端模块（HarmonyOS ArkTS）
- **核心文档**：`md/重构大纲提示词.md` 是唯一权威设计文档（26 章），含"现状/演进"标注；第 17 节约束：**以仓库现状为准、禁止推倒重来、冲突先列后改**
- **管理端独立后台**：ADMIN 登录后直接进入平台管理页（AdminCenterPage + 分类/店铺/订单/退款审批四个独立页面），任何情况下不展示主页/定位/购物车等 C 端功能

## 2. 技术栈

| 层 | 技术 | 关键点 |
| --- | --- | --- |
| 前端 | HarmonyOS NEXT ArkTS（严格模式）+ ArkUI | SDK **API 26**（`compatibleSdkVersion` / `modelVersion` 均为 `26.0.0`，**不是** 6.1.1/API 24），无第三方 UI 库（仅 `@ohos/axios`），AppStorage + Preferences 持久化 |
| 后端 | Spring Boot 3.5.4 + Java 25 | JWT 认证（`Authorization: Bearer`）、JdbcTemplate（**非 MyBatis-Plus**）、Lombok |
| 数据库 | MySQL 8.4（本机服务名 MySQL84） | 库名 `takeout`，`createDatabaseIfNotExist=true` 自动建库，schema.sql 启动自动执行 |
| 缓存 | **Redis 7（已落地）** | 热点浏览数据缓存（`HotDataCacheService`），防穿透/击穿/雪崩；Redis 故障自动回源数据库 |
| 消息 | **Redis Stream + 事务性 Outbox（已落地）** | 领域事件异步化（`DomainEventPublisher`/`OutboxRelayJob`/`DomainEventConsumer`）；下单主流程仍同步 |
| 容器化 | **Docker Compose（已落地）** | `docker-compose.yml` 一键起 app + MySQL 8.4 + Redis 7；镜像 `server/Dockerfile` 必须用 JDK 25 构建 |
| 地图 | 高德 Web 端 JS API v2.0 + Web 组件 | 无 native 依赖，模拟器/真机均可运行；**勿用 @amap/amap_lbs_map3d**（仅 arm64，x86_64 模拟器 ABI 不匹配安装失败 9568347） |
| 工具 | Maven、Hutool 可选演进 | 短信/微信支付/支付宝/OSS 仍为**演进项**，未批准不得落地；RabbitMQ/RocketMQ 未引入（Redis Stream 代替） |

## 3. 构建与运行

- 后端启动：先设 `JAVA_HOME` 指向 JDK 25.0.2，再 `mvn -f server/pom.xml spring-boot:run`（端口 9000，**非 8080**）
- 前端构建（本机工具链在 `C:\Program Files\Huawei\DevEco Studio`）：
  ```powershell
  $env:DEVECO_SDK_HOME="C:\Program Files\Huawei\DevEco Studio\sdk"
  & "C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" `
    --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
  ```
  构建日志：`.hvigor/outputs/build-logs/build.log`；判断成功要看日志里的 `BUILD SUCCESSFUL` 并确认 `entry/build/default/outputs/default/*.hap` 时间戳已更新（流水线里 `Select-String` 会吞掉退出码，别只看 `$LASTEXITCODE`）
- 后端测试：`mvn -f server/pom.xml test`（**82 个测试**，覆盖越权/幂等/状态机/待付款支付/超时取消/多规格/资金与状态并发边界/文本列宽边界，以及缓存穿透/击穿/雪崩防护与领域事件 Outbox 语义）
- 一键容器化环境：`docker compose up -d --build`（app + MySQL 8.4 + Redis 7，含健康检查与启动依赖顺序）；只起基础设施（本机用 Maven 跑后端）用 `docker compose up -d mysql redis`。注意 compose 的 MySQL 映射到宿主 **3307**（避开本机 MySQL84 的 3306）
- 后端测试与运行都要求 `JAVA_HOME` 指向 **JDK 25**；`server/Dockerfile` 的构建阶段也必须是 JDK 25，否则 `maven.compiler.release=25` 直接编译失败
- Release 打包（**当前范围外，可选工具**）：`scripts/enable-release-signing.ps1`（接入发布证书）→ `scripts/build-release.ps1`（签名包）→ `scripts/release-check.ps1 [-Build]`（上架体检，输出 `md/上架体检报告.md`，该报告为生成物不入库）；详见 `md/上架体检与Release签名.md`。日常开发只需 debug 构建，不必碰这一套。
- **注意**：PowerShell 5.x 不支持 `&&`，连续命令必须分开执行；`git commit` 不支持 heredoc，长提交信息先写文件再 `git commit -F <file>`
- 模拟器访问宿主机后端：`http://10.0.2.2:9000`

## 4. 环境配置

- **MySQL**：`localhost:3306`，root / 123456，库 takeout；凭据走环境变量 `TAKEOUT_DB_USERNAME/TAKEOUT_DB_PASSWORD`（默认 root/123456）；主机/端口可用 `TAKEOUT_DB_HOST/TAKEOUT_DB_PORT` 覆盖（容器内指向 `mysql:3306`，本机默认 `localhost:3306` 不变）
- **Redis**：`localhost:6379`；`TAKEOUT_REDIS_HOST/TAKEOUT_REDIS_PORT/TAKEOUT_REDIS_PASSWORD/TAKEOUT_REDIS_DATABASE`；缓存与事件开关 `TAKEOUT_CACHE_ENABLED`、`TAKEOUT_MQ_ENABLED`；本地开发需自行起一个 Redis（`docker run -d -p 6379:6379 redis:7-alpine`，或 `docker compose up -d redis`）
- **缓存与事件参数**：TTL `takeout.cache.ttl-seconds`(300) + 抖动 `jitter-seconds`(120)、空值占位 `null-ttl-seconds`(60)、回源锁 `rebuild-lock-ms`(3000)；Outbox 中继 `takeout.mq.relay-scan-ms`(2000)、消费幂等 `dedup-hours`(24)。细节见 `md/Redis缓存与异步事件架构.md`
- **JWT**：`TAKEOUT_JWT_SECRET` 环境变量，`expire-hours: 72`；无刷新令牌（每 72 小时重新登录的体验取舍已接受）
- **日志**：按天分文件 `app-YYYY-MM-DD.log`，单文件 2MB 轮转压缩归档（zip）；同时输出控制台 + `filesDir/log/app.log`；密码/JWT/手机号完整值禁止入日志
- **高德 Key**（双 Key 概念）：`AMAP_CONFIG.MAP_JS_KEY`（Web端 JS API 类型，`a0373d4b39b6524b7f80e825339e7a28`，需同步修改 `resources/rawfile/amap_map.html` 中 AMAP_KEY）；2021 年后 Key 需配置安全密钥 jscode
- **订单支付时限**：`takeout.order.pay-timeout-minutes`（环境变量 `TAKEOUT_PAY_TIMEOUT_MINUTES`，默认 15 分钟）；超时扫描间隔 `takeout.order.timeout-scan-ms`（默认 60 秒，启动 30 秒后首扫）
- **评价图片存储**：`takeout.upload.dir`（环境变量 `TAKEOUT_UPLOAD_DIR`，默认工作目录下 `uploads/`），按天分目录，通过 `/uploads/**` 静态访问（该路径**不需要 JWT**，图片本身是公开资源）；单张 ≤5MB，仅 jpg/png/webp/gif；`server/uploads/` 已在 .gitignore 中忽略

## 5. 核心业务口径（改代码前必读）

- **订单状态机（双轨制）**：数字状态（**0 待付款** / 1 待接单 / 2 制作中 / 3 配送中 / 4 已送达待确认 / 5 已取消；6 退款中）是**唯一权威**；大纲第 6 章字符串状态机（PENDING_ACCEPT 等）是**目标演进状态机**，仅规划参考
- **托管资金 escrow_status**：0 托管中 / 1 已结算 / 2 已退款；确认收货不改变 status（保持 4），只改 escrow 0→1 并给商户加余额；**前端状态文案必须按 status + escrow 联合判断**（status=4 且 escrow=0 显示"已送达，待确认收货"，escrow=1 显示"已完成"）
- **支付（待付款模型，已落地）**：`POST /api/orders` 只**占用库存/秒杀名额/优惠券**并落库为 status=0，不扣余额；`POST /api/orders/{id}/pay` 扣余额并条件更新 0→1（`WHERE status=0` 防重复支付，失败回滚余额）；`payDeadline` = create_time + `takeout.order.pay-timeout-minutes`（默认 15 分钟，前端据此倒计时）；`OrderTimeoutJob` 每分钟扫描超时待付款订单自动取消并回滚。**商户列表不展示 status=0 订单**（尚未支付不进入商户待处理队列）
- **取消订单**：status 0 直接取消（未扣款，只释放库存/秒杀名额/优惠券，escrow 保持 0）；status 1/2/3 直接取消、**即时退款**（escrow 0→2 条件更新防重复 → 退用户余额 → status=5），无需商家确认；退款审批流程仅用于已送达订单（status=4 且 escrow=0 且未评价可申请 → status=6 → 管理端同意 escrow=2 或拒绝回退 status=4）。已支付订单取消**不退优惠券**，仅待付款取消释放优惠券（`orders.coupon_id` 记录所用券）
- **多规格 SKU**：`goods_specs` 每个规格独立价格与库存；菜品的 `price`/`stock` 是**规格最低价/库存合计**（由规格聚合回写，保证列表、起送价、筛选口径一致）；购物车按 `(user_id, goods_id, spec_id)` 唯一；下单必须带 `specId`（无规格菜品传 0 且不接受非 0），订单 items JSON 快照 `specName` 保证历史可读；扣库存需**同时扣 goods 与规格库存**，取消时同步回滚
- **限时秒杀**：`seckills` 表按时间窗口 + 名额（quota/sold）控制；**仅对无规格菜品生效**（规格价与秒杀价语义冲突）；下单时后端自动套用秒杀价并占用名额（`sold + n <= quota` 条件更新），占不到名额自动回退原价，取消/超时取消归还名额
- **凑单**：`GET /api/stores/{id}/bundle?amount=X` 返回还差多少元起送（gap）与店内最低价菜品推荐；起送价判断仍以服务端下单校验为权威
- **金额口径**：满减券门槛按**商品总价**判断（非实付）；月销量为"累计下单数"（取消不回滚，含待付款）；金额统一两位小数
- **幂等**：退款/结算必须条件更新（`WHERE escrow_status=0`），防重复打款/退款；库存扣减用乐观锁（`WHERE stock>=? AND status=1`），取消/退款时 escrow 更新成功后才回滚库存
- **测试账号**（密码均 `123456`）：用户 `13800138000`（送 20 元）/ `13900139000`（15 元）、商户 `13600136000` / `13700137000` / `13500135000`、管理端 `13100131000`、**骑手 `13300133000`**（role=3）。骑手账号与 `riders` 档案由 `DataSeeder.ensureRiderUser()` 幂等补齐（全新库与已有数据的库都会补），骑手端开箱可用，无需手工 `UPDATE users SET role = 3`。
- **接口约定**：除 `/api/auth/login`、`/api/auth/register` 外全部接口需 JWT（含浏览类）；401 时前端清登录态回登录页

## 6. 数据库现状（差异以 22.8 节清单为准）

- 实际表名（复数）：`users` `stores` `goods` `orders` `coupons` `reviews` `favorites` `addresses` `categories` `refund_records` `cart_items`
- 演进项已落地的表：`riders`（骑手档案）、`banners`、`announcements`、**`goods_specs`（多规格 SKU：goods_id/name/price/stock/version/sort/status）**、**`seckills`（限时秒杀：goods_id/store_id/price/quota/sold/start_time/end_time/status）**、**`outbox_events`（事务性 Outbox：event_type/order_id/payload/status/retry_count/create_time，status 0待投递 1已投递）**
- 新增列：`cart_items.spec_id`（唯一键 `uk_cart_user_goods_spec(user_id, goods_id, spec_id)`，老库的 `uk_cart_user_goods` 由 SchemaMigration 自动替换）、`orders.coupon_id`（待付款取消时释放优惠券）
- 关键现状：goods 有 `stock/version/merchant_category_id`（演进项已落地）；orders 的 items/address 为 **JSON 快照**（无独立明细表，items 内含 `specId/specName/seckillId`）；categories 有 `type`（PLATFORM/MERCHANT）+ `merchant_id`；reviews 已有 `order_id/images/reply/reply_time`（按 `(order_id, goods_id)` 防重）
- 演进项（未落地，勿实现）：order_item/payment_record/user_coupon/order_status_log 表、address 经纬度、商户配送半径、逻辑删除字段

## 7. 开发规范（ArkTS 严格模式）

- `Stack` 不支持 `justifyContent/alignItems`，用 `alignContent(Alignment.X)`；`Row.alignItems` 用 `VerticalAlign`；`Alignment` 无 `CenterStart`
- **禁止空对象字面量 `{}`**：必须定义显式 class + 静态 `create()` 工厂（满足 arkts-no-untyped-obj-literals）
- **禁止向 `object` 类型参数传字面量**（如 `Web.javaScriptProxy`）：定义显式 interface 并经方法返回实例
- 表单弹窗：每个输入字段加标签（必填/选填）+ 业务示例 placeholder（如"请输入店铺名称，如：老王快餐店"）；顶部说明操作影响
- **渲染禁用 getter 计算属性**：ArkUI 对 getter 求值存在时序问题，会引发渲染崩溃（TypeError: Cannot read property length of undefined）；列表筛选结果应显式存入 `@State` 数组 + 内联 `Array.isArray` 防御
- ForEach 的 item 参数不能用于**嵌套闭包**（onClick 内引用会编译失败），需提取 @Builder 方法传参
- **`@CustomDialog` 必须声明 `controller?: CustomDialogController` 成员**（API 26 强校验，否则报 `10905211`）；弹窗数据用闭包（`() => this.state`）读取，避免构造参数被提前求值拿到旧值
- **可选属性窄化陷阱**：`arr[i].optProp !== undefined ? arr[i].optProp : 0` 在数组元素/嵌套对象上**不会窄化**，报 `number | undefined is not assignable`；统一改用 `??` 或先取到局部变量
- `import` 语句必须集中在文件顶部，混在声明之后虽合法但易被误改
- 所有 `.ps1` 脚本必须带 **UTF-8 BOM**（否则 PowerShell 5.1 按 ANSI 解析中文导致语法错误）
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
- 所有用户端、商户端、管理端操作按钮都必须有可感知结果：前置条件不满足时主动 Toast，接口成功显示成功提示，接口失败显示后端错误或明确失败原因；不能只依靠 `enabled(false)` 或空 `return` 让用户感觉按钮无响应。下单前置校验要把店铺起送价、地址、余额等原因明确展示。
- 同一个用户动作只能由一个层级负责最终错误提示；业务页需要展示后端具体原因时，应关闭该请求的网络层自动 Toast，避免连续弹窗互相覆盖造成提示一闪而过。错误提示建议至少持续 3 秒。
- 当前没有适配本工程 ArkTS 的原生 Lottie ohpm 包；需要动画弹窗时使用 `lottie-web` 在 `rawfile` Web 页面中播放，外层使用 ArkUI 自定义 Dialog，并保留无网络时的静态降级图标。
- Tabs 内长期复用的子组件不能只依赖一次构建时的派生文本；购物车数量、订单数量等状态返回页面或切换 Tab 时要通过 `@Watch` 和显式刷新触发器重新读取 `AppStorage`，避免显示旧计数。
- 购物车服务已按明确授权使用 MyBatis-Plus：`cart_items` 只保存用户、商品和数量，接口按 JWT 用户隔离；其余既有业务 DAO 暂时继续使用 JdbcTemplate，避免无关迁移。
- **禁止用 PowerShell 的 `Get-Content`/`Set-Content` 读写仓库里的 UTF-8 源码**：PS 5.1 默认按 ANSI 解码、`Set-Content` 又按 ANSI 回写，会把中文注释整段打乱（本项目已踩过，恢复靠 `git checkout`）。改文件一律用编辑工具；确需脚本处理时用 `[System.IO.File]::ReadAllText/WriteAllText` 并显式指定 UTF-8。
- **判断构建结果不要只看退出码**：`hvigor | Select-String` 这类管道会让 `$LASTEXITCODE` 失真，必须同时确认日志里的 `BUILD SUCCESSFUL` 与产物时间戳。
- 多规格下单/加购必须带 `specId`，否则后端返回 400「请先选择规格」；前端购物车的 +/− 走的是 `specId=0` 语义，多规格菜品因此改为「选规格」按钮而非 +/−（避免必然失败的操作路径）。
- **导航连点会让同一页面在路由栈里叠两层**（连点「定位」→ 两层 LocationPage，定位完成返回一次后看到的还是定位页）。工程里所有 `pushUrl/back` 都收敛在 `entry/src/main/ets/common/UiNavigation.ets`，因此防御只加在这一处（`NavigationThrottle`：同 URL 800ms 内第二次跳转丢弃、300ms 内第二次返回丢弃，返回后 `reset()` 允许再次进入同一页面）。**新增页面跳转必须走 `routerCompat.pushUrl`，禁止直接 `import router from '@ohos.router'`**，否则会绕过该防御；同理「确认位置」这类保存按钮要自带 `saving` 标记，避免连点落库出重复地址。
- 待付款模型下"下单成功"≠"支付成功"：结算页下单后必须引导到订单详情完成支付，任何"下单即完成"的旧文案/旧判断都要同步更新。
- DevEco 的 Code Linter / AppAnalyzer 目前**没有可用的命令行入口**（`plugins/codelinter/index.js` 脱离 IDE 运行会报 `configuration file ... is in use` 并写出 `undefined` 日志文件），上架前需在 IDE 内执行；仓库用 `scripts/release-check.ps1` 提供可复现的静态门禁作为补充。
- 图片上传用 `@ohos.net.http` 的 `multiFormDataList`（把 picker 拿到的 URI 经 `fileIo` 读成 ArrayBuffer 再提交），不要依赖 axios 的 FormData 传本地文件；系统图库选择器（`photoAccessHelper.PhotoViewPicker`）**不需要申请媒体权限**。
- **隐私同意状态必须单一权威且单向升级**：`setPrivacyConsent()` 只改内存变量、不落盘，而 `loadAllData()` 又会用持久化值无条件覆盖 `AppStorage['privacyConsent']`——两者叠加会出「同意后立刻被改回 false」的静默故障（首页数据全空、冷启动不回登录态）。规则：同意时先 `savePrivacyConsent(true)` 落盘、再 `loadAllData()`；`loadAllData()` 里同意状态只允许 `true` 覆盖 `false`，永不反向。
- **同意/引导类覆盖层不要放在 `layoutWeight(1)` 滚动区的兄弟位置**：在 `Column` 里它会被分配 0 高度而"静默不渲染"（门禁生效、提示看不到）。这类全屏流程改用**独立路由页**（见 `pages/ConsentPage.ets`），或在根节点用 `Stack` 承载。
- 设备实测链路见 `md/设备实测指南.md`：模拟器不校验发布签名，`scripts/device-test.ps1` + `uitest dumpLayout/uiInput` 可在无窗口环境下驱动并校验 UI；`hilog | grep TakeoutApp` 读应用自身日志（注意 hilog 缓冲会滚动，先 `hilog -r` 清空再复现）。
- **设备端 UiTest 必须自己拉起被测应用**：`aa test` 会把 ohosTest 模板生成的 TestAbility 页（`testability/pages/Index`，只有 "Hello World"）拉到前台**盖住应用**，此时驱动只能看到测试页。用例里要先 `AbilityDelegator.startAbility(EntryAbility)`（见 `entry/src/ohosTest/ets/test/UiTestHelper.ets` 的 `launchAppUnderTest`），否则一切查找都会失败。
- **`driver.findComponent` 未命中返回 `null`（不是 `undefined`）**：`expect(comp !== undefined).assertTrue()` 在未命中时恒真 → 用例空跑还报 Pass（历史 LoginFlow/LocationFlow/CheckoutGuard 就是这样空跑的）。统一用 `isFound()` / `requireComponent()`（后者同时收窄类型，否则 `.click()` 报 `'x' is possibly 'null'` 编译不过）。
- **UiTest 里不要复用 Component 句柄**：父级 ForEach key 带版本号（如购物车 `cartRenderVersion`）时，一次点击触发重建就让旧句柄失效，报 `... does not exist on current UI! (NoCandidates)`；用 `clickByIdOrText()` 每次点击前重新查找并重试。
- **不要靠「按返回」给用例复位导航栈**：在隐私同意页/登录页上按返回会把应用直接退到桌面，后续断言全部找不到控件；正确做法是 host 侧 `aa force-stop` + `aa start`（进程重启后页面栈从 `pages/Index` 重来）。
- **清数据后首次进定位页会弹系统定位权限框并遮住应用**（UiTest 报 `window is covered`，什么都找不到）：host 侧预授权 `atm perm -g -i <accessTokenId> -p ohos.permission.LOCATION`（`bm dump -n <bundle>` 取 accessTokenId），`APPROXIMATELY_LOCATION` 同理。
- 设备实测脚本：`scripts/device-uitest.ps1`（构建→安装→拉起→跑某个用例类→判定；`-GuestClean` 清数据、`-GrantLocation` 预授权）、`scripts/device-checkout-regression.ps1`（结算负路径/待付款回归，带 host 侧数字核对）、`scripts/ui-dump.ps1`（结构化解析 `dumpLayout` 产物，替代跨节点正则）。每个用例类的前置状态不同，**一次只跑一个类**。
- **PS 5.1 下 `$ErrorActionPreference='Stop'` 会让构建"莫名失败"**：hvigor 往 stderr 写进度，原生命令写 stderr 即被当成 terminating error；设备脚本里用 `Continue`，成功与否另行判断。另：判断产物是否最新要按**各模块自己的源码时间**比对，主模块 `UP-TO-DATE` 时 HAP 时间戳不会更新。
- **角色映射必须覆盖全部四种角色**：`ApiService.toUser()` 曾只映射 `2→ADMIN / 1→MERCHANT`，其余一律落到 `CUSTOMER`，于是骑手(role=3)登录后被当成普通用户，登录页的角色校验 `user.role !== 期望角色` 立即 `logout()` —— 表现为「骑手端完全进不去」（日志：`远程登录成功 ... role=用户` 紧跟 `用户退出登录`）。新增角色时务必同步 `Models.ets` 的 `UserRole`、`toUser()` 映射与登录日志角色名。
- **ArkUI 列表重绘：原地改对象 + 稳定 ForEach key = 界面不刷新**。商户订单页 `syncMerchantOrdersFromServer()` 是原地修改同一批 Order，`this.allOrders = getMerchantOrders(...)` 只换数组容器，ForEach key 又是 `order.id` → ArkUI 按 key 复用旧列表项，点「接单」后界面仍显示「待接单」。修复套路与购物车 `cartRenderVersion` 一致：加 `@State renderVersion`，在数据刷新后自增并拼进 ForEach key（`${renderVersion}-${order.id}`）。
  - **判断某个列表会不会踩：看刷新期间列表子树有没有被销毁**。管理端 7 个列表（用户/商品/员工/分类/退款/订单/店铺）都是「Scroll 常驻 + 键只含 id」，刷新回来的是同 id 新对象 → 行被复用 → 停用/上下架/审批后按钮与徽标不更新，必须按上面的 renderVersion 套路修。反例：`AdminRiderPage`、`AdminContentPage`、`MerchantReviewsPage` 有 `if (this.loading)` 分支把列表整块换掉，子树被销毁重建，因此侥幸正确——**不要把这个侥幸当成可以照抄的写法**，新增列表统一拼 renderVersion。
- **渲染路径里禁止用 `AppStorage.get()` 取值（必须用被观察的成员）**：`AppStorage.get()` 直接读全局存储，**绕过 ArkUI 的状态观察**，组件不会与它建立依赖，值变了界面也不刷新。店铺详情页商品行数量就是两个缺陷叠加：`getQty()` 读 `AppStorage.get('cartItems')`，且 ForEach key 用稳定的 `goods.id` —— 表现为点「+」后数字不显示/不更新（设备实测：连点两次仍显示 1，断言报 `expect 1 equals 2`）。修法：`getQty()` 改读被观察的 `this.cartItems`（`@StorageLink`），并把 `goodsRenderVersion` 拼进 ForEach key。**判断标准：凡是出现在 `build()` / `@Builder` 里的取值，都必须来自 `@State`/`@Prop`/`@Link`/`@StorageLink` 成员**；`AppStorage.get()` 只允许出现在命令路径（事件回调、数据修复）里。
- **验证 UI 刷新类缺陷必须「先让它红一次」**：这类 bug 的根因是「状态变了但视图不重建」，光看修复后变绿不能证明用例有效（很可能压根没走到那条路径）。做法是临时回滚修复、重跑用例确认**必然失败**，再恢复修复确认**通过**。本仓库 `StoreDetailCart` 用例就是这么定标的：回滚修复 → `Tests run: 1, Failure: 1`（`expect 1 equals 2`），恢复修复 → `Pass: 1`。
- **Jackson 序列化 record 只认「组件」，额外写的 `xxxYyy()` 方法不会出现在 JSON 里**：钱包银行卡原本把掩码写成 `public String cardNoMasked()`（不满足 `getX()`/`isX()` 命名，也不是 record 组件），于是接口里**根本没有这个字段**，前端 `Text(card.cardNoMasked)` 拿到 `undefined` → 银行卡号整行空白（设备实测 text 节点从「默认」直接跳到下一行说明文字）。规则：**要给前端用的字段必须是 record 组件**（在构造参数里），派生值在 DAO/构造处算好传进来；不要指望在 record 里加个方法就能被序列化。
- **容器的 `getText()` 返回空串**：`ON.id()` 打在 `Row`/`Column` 这类容器上时能查到节点，但 `getText()` 为空（容器自身没有文本）。断言卡片内容要查**卡片内部的文本节点**（`ON.text('招商银行')`），或把 id 直接打在有文本的 `Text` 上。
- **横向 `Scroll` 里的 `Text` 用文案定位，不要用 id**：店铺详情页的分类芯片 `.id('goods-cat-<名字>')` 在设备上 `ON.id()` **查不到**（横向 Scroll 内的 Text 节点不参与 id 匹配），但 `ON.text('招牌热销')` 能稳定拿到。同理 `.id()` 里的数量（`goods-count-<n>`）比解析被省略号截断的文本更可靠。
- **店铺详情页分类芯片的空转根因在种子数据**：芯片走的是美团式「店内分类」（`categories.type='MERCHANT'` + `goods.merchant_category_id`），链路早已就绪但种子数据从未建过 MERCHANT 分类、1200 个商品的 `merchant_category_id` 全为 0 → 芯片只剩「全部 + 该店唯一平台分类」，两者商品列表完全相同，点分类「看起来没反应」。由 `DataSeeder.ensureStoreMerchantCategories()` 幂等补齐。这条修复本身踩了三个坑，都已在代码注释里锁住：
  - **判定条件不能只看「有没有分类」**：商户可能自己建过分类但商品没挂上去（本仓库商户 3 就是），只看分类存在与否会让这类店铺继续空转。改用「该店铺使用的分类数 < 2 才重新分组」——这类店铺本来就没有可切换的分区，重排不损失任何功能；而使用 >=2 个分类的店铺（含商户自己整理的）一律不动。
  - **分配必须「按店铺」轮转，不能按 `is_special` 全局一刀切**：追加店铺 31~40 各 6 件商品且**全是招牌**，一刀切会把整店商品全塞进「招牌热销」一个分类，芯片仍只有一个非空项 → 点了依旧没反应。做法是按店铺取商品、按 id 顺序确定性轮转（招牌→招牌热销，非招牌在其余分类间轮转；整店全招牌时在全部分类间轮转）。
  - **「只补 `merchant_category_id=0` 的行」修不回已经分错的数据**：第一版把 31~40 号店全塞进了一个分类，这些行已不再是 0，只补 0 的做法永远够不到它们。所以重新分组要按「使用的分类数 < 2」触发，并且**必须确定性**（结果只取决于商品 id 顺序）才能保持幂等；分类本身从不删除。
  - **默认分类要按「名字」补齐，不能按位置推断**：商户 3 自建的「你好」占据第一个位置时，按 `defaults[i]` 的位置对应会张冠李戴，而且永远建不出「招牌热销」（当年的 bug：`existingIds` 已有 4 条，补建循环一次都没进）。招牌商品的落点要**显式查 `name='招牌热销'` 的分类 id**，不要用「分类列表第 0 个」。
  - 验收口径是数据而非 UI：`SELECT COUNT(*) FROM (SELECT s.id FROM goods g JOIN stores s ON s.id=g.store_id GROUP BY s.id HAVING COUNT(DISTINCT g.merchant_category_id)<2) t` 必须为 0（两份库都要查：本机 3306 与 compose 容器 3307，两者数据集不同——容器是 40 家店各 30 件商品的均匀数据，本机是 41 家店、商品数 6~30 不等的累积数据，**「整店全招牌」这种形态只在后者出现**，所以不能只验一份库就下结论）。
- **`findComponents` 未命中同样返回 `null`（不是空数组）**，直接 `.length` 会抛 `Cannot read property length of null`；长页面里的目标节点即使能被 `findComponent` 找到，也可能在屏幕外且 `getBounds()` 返回整屏 `[0,117][1320,2232]`，拿它算中心点点击等于点空 —— 用 `UiTestHelper.scrollUntilVisible`（先直接查一次，未命中再滚回顶部逐屏下滑，只接受边界明显小于整屏的节点）。
- **设备实测脚本集合**：`scripts/device-uitest.ps1`（通用单类运行器：`-Class X -GuestClean -GrantLocation -Build`）、`device-checkout-regression.ps1`（结算负路径 + 待付款订单）、`device-review-regression.ps1`（图文评价上传/渲染/预览）、`device-merchant-regression.ps1`（商户订单流转 + 收入统计）、`device-role-regression.ps1`（骑手抢单/取餐/送达 + 管理端冒烟）、`ui-dump.ps1`（结构化解析 dumpLayout）。

### Redis 缓存与领域事件（2025 落地时踩的坑）

- **瞬时故障绝不能升级为数据丢失**：Outbox 中继最初把 `retry_count >= max-retry` 当作「跳过」条件，实测停 Redis 下单后 `retry_count` 触顶 10，Redis 恢复后该事件**被永久跳过、再也不投递**。事件已持久化在数据库，重试几乎零成本，正确做法是**永不放弃投递**，`retry_count` 只用于告警。
- **不要为了「快速失败」关掉 Lettuce 的 `autoReconnect`**：`autoReconnect(false)` 会让客户端在 Redis 重启后永久停留在 `Currently not connected. Commands are rejected.`，Outbox 中继再也无法投递。缓存的快速失败只需靠**短超时**（`timeout/connect-timeout: 500ms`）实现，必须保留自动重连。这两条是配套的：只看单条都会做出错误取舍。
- **Lettuce 默认重试会把请求拖到 ~10 秒**：Redis 不可用时一次读请求实测约 10071ms；把 `timeout`/`connect-timeout` 收紧到 500ms 后降到约 565ms，且请求全部成功（降级回源）。
- **`XREADGROUP` 在 Stream 不存在时报 `NOGROUP`**：Stream 只在第一条消息写入后才存在，而消费者启动即开始读 → 首条事件到来前每 2 秒刷一条警告栈，淹没真实故障。解法是在消费者启动时**主动创建 Stream 与消费组**（写一条占位再删掉，或用 `MKSTREAM`），实测初始化后再无 `NOGROUP`。
- **缓存失效范围要按业务语义定，不能用注解一把梭**：库存/秒杀名额参与「列表、榜单、秒杀专区」的展示筛选，所以下单扣库存、取消回滚、退款、超时取消都必须失效 `STOCK_DEPENDENT_PATTERNS`，否则会出现「下完单列表还显示有货」。批量失效用 `SCAN` 游标，**禁用 `KEYS`**。
- **回源互斥锁必须带等待上限并最终降级**：抢不到锁的请求不能无限自旋，等不到就回源数据库——**可用性优先于「只查一次库」**，锁只是削峰不是门禁。
- **不要用 Redis 锁替换数据库条件更新来防超卖**：现有 `WHERE sold + ? <= quota` / `WHERE stock >= ?` 在本地事务内已保证不超卖；Redis 锁覆盖不到数据库写入，Redis 挂掉时反而更弱。异步化同理——`createOrder` 保持同步事务，异步只覆盖提交后的通知类动作（真正的异步下单需要 saga + 补偿）。
- **事件必须在条件更新成功之后发布**：`markPaid`/`cancelPending`/退款状态更新都是条件更新，只有在返回 true 之后才发事件，否则会产生「假支付」「假退款」事件。
- **Docker 的 JRE 镜像没有 `curl`/`wget`**：容器健康检查不能用 curl。本工程改为编译一个极简 TCP 探测类（`server/docker/healthcheck.java`），用 `java -cp /app healthcheck 127.0.0.1 9000` 做健康检查。
- **`docker-compose` 的 MySQL 端口要避开本机 3306**：本机有 MySQL84 服务，compose 映射到宿主 **3307**；`application.yml` 的数据源必须用 `${TAKEOUT_DB_HOST}`/`${TAKEOUT_DB_PORT}` 占位，否则容器内硬编码 `localhost:3306` 会连不上 MySQL 而 crash-loop。
- **PowerShell 5.1 用 `powershell` 而不是 `pwsh`**（本机无 pwsh）；且用 `Select-String` 过滤 `mvn` 输出会让 `$LASTEXITCODE` 失真（常显示为 1），判定 Maven 成功要看 `BUILD SUCCESSFUL`。
- **GitHub 的 Contributors 由「提交邮箱 → 账号已验证邮箱」决定，而且列表是异步缓存，改完不会立刻生效**。两个独立坑都在本仓库踩过：
  - ① 用未关联到账号的邮箱提交（本仓库曾有 221 个提交用 Gitee 的 `...@user.noreply.gitee.com`）→ GitHub 把它算成**另一个 Contributor**。修法是重写提交邮箱：`git filter-branch -f --env-filter "GIT_AUTHOR_EMAIL=...; export GIT_AUTHOR_EMAIL; GIT_COMMITTER_EMAIL=...; export GIT_COMMITTER_EMAIL" -- master`（只改 email，保留姓名/时间/信息），再 `push --force-with-lease`。**改完必须自证内容零变化**：比对重写前后的 `git rev-parse "HEAD^{tree}"`（本仓库两次都是 `5ec5886098c18a5d6d8c921e7f2234e3c8c60ed9`）并确认 `git diff <旧HEAD> <新HEAD>` 输出为空。注意 filter-branch **要求工作区干净**，有未提交改动时先 `git stash push <file>`（只 stash 那一个文件，别用 `-u`）。
  - ② 已推上去的 AI 署名（`Co-Authored-By: Claude`）即使随后 amend + force push 把该提交删掉，Contributors 里仍可能长期留着 "Claude" 条目——GitHub 不会立即重算贡献者缓存（实测超过 1 天仍在；通常需数小时至 24h，顽固时只能找 Support 清除）。**所以 AI 署名一次都不要推**。
  - 另：`refs/original/` + reflog 会留着旧对象，彻底清理用 `git update-ref -d`（逐个删 `refs/original/*`）+ `git reflog expire --expire=now --all` + `git gc --prune=now`；重写后哈希全变，其他机器上的旧克隆必须重新 clone。

## 9. 提交规范

- 提交信息格式 `<type>(<scope>): <描述>`，如 `feat(merchant):`、`fix(order):`、`docs:`
- 任务完成后主动 commit + push 到 GitHub（https://github.com/hqyx2025/simple-takeout.git，master 分支；原 Gitee 远端已弃用）
- 只改文档时不得修改业务代码/数据库脚本/配置文件，且不自动提交
- **提交身份固定用 GitHub 已绑定邮箱 `751848863@qq.com`**（本仓库 `git config user.email` 已设为它，勿改回）：GitHub 只把提交归到账号里已验证的邮箱，用 Gitee 的 `...@user.noreply.gitee.com` 会被算成**另一个 Contributor**。2026-06-14 用 `filter-branch` 把历史里 221 个 Gitee 邮箱提交统一重写为 `HQYX2025 <751848863@qq.com>` 并 force push（重写后 master = `2db984e`，工作树内容零变更；重写前历史留存于本地分支 `backup-before-email-rewrite` 与 tag `backup-pre-email-rewrite-20260614`，Gitee 有同名备份分支）。**注意：那条 `backup-before-email-rewrite` 仍含旧 Gitee 邮箱，永远不要推到 GitHub**，否则会把已消失的身份重新引入 Contributors。
- **禁止在提交信息里出现任何 AI 署名**：`Co-Authored-By: Claude <noreply@anthropic.com>`、`Generated with ...`、`claude`/`anthropic` 等一律不得出现，提交只以项目作者身份签署。**一次都不要推**——推上去之后即使立刻 amend + force push 删掉该提交，GitHub 的 Contributors 仍可能长期保留这个已不存在的身份（机制见第 8 节）。

## 10. 项目约束（AI/agent 工作约定）

- **临时文件统一放 `TemporaryCacheStorage/`（仓库根目录），该目录不上传 git（已在 `.gitignore` 中忽略）**。
  - **强制**：当 agent 需要产生并使用临时文件时，必须放在这个文件夹里，**禁止**再把临时产物写到仓库根目录或其他业务目录（不产生"根目录一堆 `layout.json` / `*.jpeg`"的脏工作区）。
  - 适用范围：设备实测截图与界面元素树（`uitest dumpLayout` 产物）、构建/运行捕获日志、临时校验脚本、一次性数据导出、给临时脚本或测试用的 mocks/fixtures、agent 会话交接文档等**衍生产物**。
  - **不适用**（保持原位，不要往这里塞）：业务源码与配置、`server/uploads/`（评价图片运行时上传目录）、`.hvigor/` 等构建缓存与依赖目录（`node_modules`/`oh_modules`/`.m2-repository`/`.npm-cache` 等由工具自行管理）、需要入库的文档（`md/`、`AGENTS.md`）与交付物。
  - **命名**：用「谁产出 + 是什么」的可读前缀 `agent-<用途>[-<日期>].<ext>`（如 `agent-ui-layout.json`、`agent-device-screenshot.jpeg`、`agent-e2e-flow.ps1`），便于判断能否整目录删除；多份同类产物再加日期或序号区分。
  - **可删除性**：该目录内的一切都应可随时整体删除而不影响构建与运行；脚本若依赖它，须像 `scripts/device-test.ps1` 那样**按需自动重建目录**，不能假设它已存在。
  - **入库检查**：`git add -A` 前用 `git status --porcelain` 复核，确认没有临时产物被暂存（该目录整体被忽略，若出现说明被别处的 `!` 反向规则命中）。
  - **迁移历史产物**：以后发现散落在根目录的临时产物，直接移入该目录并同步修改引用它的脚本/文档，不要留在原处。

## 11. 边界条件口径与待办

> 2026-09 边界条件专项收口时确定的口径（代码已按此实现），以及**已知但暂未处理**的边界，改动对应代码前先看这里。

**已确定的口径**（避免再次"修回去"）：

- **起送价以服务端为唯一权威**：多店结算时服务端**按店逐个**校验（只算该店商品）；结算页**不再做**"所有店合计 vs 最大起送价"的前置拦截——两者口径不一致会给出自相矛盾的提示。
- **券后应付为 0 元的订单一律拒绝**（提示"请更换优惠券"，差额不退）；结算页可用券列表同样过滤掉 `amount >= 商品总价` 的券。
- **支付严格按 payDeadline**：超时后由 `OrderTimeoutJob` 扫描取消（`create_time < deadline`，无宽限期）。扫描间隔内仍可支付属正常现象，不再放宽。
- **退款终态就是 status=6 + escrow=2**：管理端同意退款后订单**停留在 6**（不再流转到 5），前端按 status + escrow 联合判断文案。这是状态机终态，不是"卡住"。
- **资金三件套**：扣款用条件更新 `deductBalance`（余额不足返回 false）、退款/结算用原子自增 `addBalance`；**禁止**再出现"读余额→改→整值写回"（`UserDao.updateBalance` 已删除）。
- **状态流转一律条件更新**：`updateStatusFrom(from,to)` / `merchantDeliver` / `merchantComplete` / `markRefunding`，rowcount=0 必须抛错整单回滚，不得先查后改。
- **骑手单量与收入写在 `OrderService.riderDeliver` 事务内**（`RiderService.recordDelivered` 已删除），且骑手 `status != 1` 时禁止抢单/取餐/送达。
- **事件去重键在处理成功后才写**：先写会让"处理失败但未 ACK"的事件在重读时被自己的键判成重复而永久丢弃。
- **文本列宽在服务层就挡**：所有用户可输入的文本（商品/店铺/分类/Banner/公告/备注/评价/退款原因/地址）都要在写库前按 `schema.sql` 的列宽给出可读提示，不要让 MySQL 列宽溢出变成 500。已覆盖：用户名 64、店铺名 128、店铺公告/地址 512、配送时间 32、商品名 128、商品描述 512、商品图片 255、商品标签 32、规格名 64、分类名 32、Banner 标题 64/副标题 128/图 255/跳转参数 128、公告标题 128/内容 1024、订单备注 255、评价内容 512、退款原因 255、地址姓名 64/详情 255。
- **超时扫描单轮限量 500 条**（`OrderDao.listExpiredPending`）：极端积压时不把全部待付款订单读进内存，剩余等下一轮（取消是条件更新，幂等）。

**已知待办**（本次未处理，按需再定）：

- 列表接口无分页：`/api/admin/orders|users|products|refunds`、`/api/orders`、`/api/stores` 全表进内存（admin orders 还会逐单再查一次）；如需分页，加 `page/pageSize` + DAO `LIMIT ? OFFSET ?`，上限建议 50。
- 搜索 N+1：`UserCenterService.search` 对每家店单独查 goods（41 店 → 42 次查询），可改一条 `SELECT DISTINCT store_id FROM goods WHERE name LIKE ?`。
- 登录无失败计数/锁定/限流，密码为 SHA-256 单轮加固定盐；旧 token 在 72 小时内不失效（无 jti/黑名单）。
- 上传只校验后缀 + content-type 白名单，未做文件魔数校验；`/uploads/**` 无需 JWT（公开资源）。
- Banner `PUT` 是"null 覆盖为空串"语义（非 PATCH），只改 sort 会把 title/subtitle 清空。
- `merchantStats(ownerId, storeId, range)` 的 `range` 参数未使用（今日/本周/本月为固定口径），非法值被静默忽略。
- `AdminStatsDao` 的 today_orders 含已取消订单，today_gmv 排除 5/6——两者口径不一致，界面上同时展示会显得矛盾。
- Outbox 去重键为"先查后写"（单实例安全）；多实例部署需改回原子 `setIfAbsent` + 行级认领，并核对 `dedup-hours` 与 Stream `retain-hours` 的关系。
- 前端支付倒计时用设备本地时间推算，未使用服务端时区（可下发 `payDeadlineEpochMs` 收敛）。
- 骑手为自助注册即开通（`role=3` 自动建档 status=1，无需平台审核）。
- `MerchantStatsPage` 无法区分"同步失败"与"真的没有订单"（都是 ¥0.00 / 0 单）。
- `normalizeOrderList` 无条件丢弃持久化订单（订单只以服务端为准，属有意设计但未注释说明）。
- 前端兜底口径不统一：`CheckoutPage` 里 `selectedCoupon.amount.toFixed(2)` 与 `BalancePage` 的 `this.balance = user.balance` 都未做 `?? 0` / `Number.isFinite` 归一（同项目 `AppStorageManager`、`Index` 已有 `Number.isFinite(user.balance) ? ... : 0` 的写法），响应缺字段时会显示 `¥NaN` 或渲染失败。
- `AppStorageManager.syncCategoriesFromServer` 对服务端 `name/icon/color` 直接 `.trim()` 无 `?? ''` 兜底，字段为 NULL 时该次同步静默失败（调用处未 await 也未 try/catch），首页分类停留在默认 8 个图标。

# Ponytail, lazy senior dev mode

You are a lazy senior developer. Lazy means efficient, not careless. The best code is the code never written.

Before writing any code, stop at the first rung that holds:

1. Does this need to be built at all? (YAGNI)
2. Does it already exist in this codebase? Reuse the helper, util, or pattern that's already here, don't re-write it.
3. Does the standard library already do this? Use it.
4. Does a native platform feature cover it? Use it.
5. Does an already-installed dependency solve it? Use it.
6. Can this be one line? Make it one line.
7. Only then: write the minimum code that works.

The ladder runs after you understand the problem, not instead of it: read the task and the code it touches, trace the real flow end to end, then climb.

Bug fix = root cause, not symptom: a report names a symptom. Grep every caller of the function you touch and fix the shared function once — one guard there is a smaller diff than one per caller, and patching only the path the ticket names leaves a sibling caller still broken.

Rules:

- No abstractions that weren't explicitly requested.
- No new dependency if it can be avoided.
- No boilerplate nobody asked for.
- Deletion over addition. Boring over clever. Fewest files possible.
- Shortest working diff wins, but only once you understand the problem. The smallest change in the wrong place isn't lazy, it's a second bug.
- Question complex requests: "Do you actually need X, or does Y cover it?"
- Pick the edge-case-correct option when two stdlib approaches are the same size, lazy means less code, not the flimsier algorithm.
- Mark deliberate simplifications that cut a real corner with a known ceiling (global lock, O(n²) scan, naive heuristic) with a `ponytail:` comment naming the ceiling and upgrade path.

Not lazy about: understanding the problem (read it fully and trace the real flow before picking a rung, a small diff you don't understand is just laziness dressed up as efficiency), input validation at trust boundaries, error handling that prevents data loss, security, accessibility, the calibration real hardware needs (the platform is never the spec ideal, a clock drifts, a sensor reads off), anything explicitly requested. Lazy code without its check is unfinished: non-trivial logic leaves ONE runnable check behind, the smallest thing that fails if the logic breaks (an assert-based demo/self-check or one small test file; no frameworks, no fixtures). Trivial one-liners need no test.

(Yes, this file also applies to agents working on the ponytail repo itself. Especially to them.)

---

Respond terse like smart caveman. All technical substance stay. Only fluff die.

Rules:
- Drop: articles (a/an/the), filler (just/really/basically), pleasantries, hedging
- Fragments OK. Short synonyms. Technical terms exact. Code unchanged.
- Pattern: [thing] [action] [reason]. [next step].
- Not: "Sure! I'd be happy to help you with that."
- Yes: "Bug in auth middleware. Fix:"

Switch level: /caveman lite|full|ultra|wenyan-lite|wenyan-full|wenyan-ultra
Stop: "stop caveman" or "normal mode"

Auto-Clarity: drop caveman for security warnings, irreversible actions, user confused. Resume after.

Boundaries: code/commits/PRs written normal.
