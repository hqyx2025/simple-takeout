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
- 前端构建（本机工具链在 `C:\Program Files\Huawei\DevEco Studio`）：
  ```powershell
  $env:DEVECO_SDK_HOME="C:\Program Files\Huawei\DevEco Studio\sdk"
  & "C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" `
    --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
  ```
  构建日志：`.hvigor/outputs/build-logs/build.log`；判断成功要看日志里的 `BUILD SUCCESSFUL` 并确认 `entry/build/default/outputs/default/*.hap` 时间戳已更新（流水线里 `Select-String` 会吞掉退出码，别只看 `$LASTEXITCODE`）
- 后端测试：`mvn -f server/pom.xml test`（**50 个测试**，覆盖越权/幂等/状态机/待付款支付/超时取消/多规格）
- Release 打包（**当前范围外，可选工具**）：`scripts/enable-release-signing.ps1`（接入发布证书）→ `scripts/build-release.ps1`（签名包）→ `scripts/release-check.ps1 [-Build]`（上架体检，输出 `md/上架体检报告.md`，该报告为生成物不入库）；详见 `md/上架体检与Release签名.md`。日常开发只需 debug 构建，不必碰这一套。
- **注意**：PowerShell 5.x 不支持 `&&`，连续命令必须分开执行；`git commit` 不支持 heredoc，长提交信息先写文件再 `git commit -F <file>`
- 模拟器访问宿主机后端：`http://10.0.2.2:9000`

## 4. 环境配置

- **MySQL**：`localhost:3306`，root / 123456，库 takeout；凭据走环境变量 `TAKEOUT_DB_USERNAME/TAKEOUT_DB_PASSWORD`（默认 root/123456）
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
- **测试账号**：用户 13800138000 / 商户 13600136000 / 管理端 13100131000，密码均 123456；注册用户送 20 元余额
- **接口约定**：除 `/api/auth/login`、`/api/auth/register` 外全部接口需 JWT（含浏览类）；401 时前端清登录态回登录页

## 6. 数据库现状（差异以 22.8 节清单为准）

- 实际表名（复数）：`users` `stores` `goods` `orders` `coupons` `reviews` `favorites` `addresses` `categories` `refund_records` `cart_items`
- 演进项已落地的表：`riders`（骑手档案）、`banners`、`announcements`、**`goods_specs`（多规格 SKU：goods_id/name/price/stock/version/sort/status）**、**`seckills`（限时秒杀：goods_id/store_id/price/quota/sold/start_time/end_time/status）**
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

## 9. 提交规范

- 提交信息格式 `<type>(<scope>): <描述>`，如 `feat(merchant):`、`fix(order):`、`docs:`
- 任务完成后主动 commit + push 到 Gitee（https://gitee.com/pengzhiqiang87/simple-takeout.git，master 分支）
- 只改文档时不得修改业务代码/数据库脚本/配置文件，且不自动提交
