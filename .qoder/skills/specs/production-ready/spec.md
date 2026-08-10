# 简单外卖可实装迭代 Spec（Production-Ready）

## Why
项目已完成完整业务闭环（用户端搜索-下单-评价 + 商户端接单-统计，共 15+ 路由页面），但距离"可实装"（可安装、可上架）仍有差距：
1. **无真实测试**：`src/test/` 仅有脚手架模板用例，核心逻辑（金额计算、状态流转、数据归一化）零覆盖
2. **无签名与发布准备**：`build-profile.json5` 的 `signingConfigs` 为空，未准备发布证书/Profile，无法构建可安装包
3. **性能未优化**：部分长列表仍用 ForEach，未使用 LazyForEach/@Reusable
4. **上架材料缺失**：无隐私政策页、应用信息未完善、版本号未管理

本 spec 参考华为官方测试服务、AppGallery Connect 发布流程与 ArkUI 性能最佳实践，将项目推进到"可实装"状态，并建立可持续迭代的开发规范。

## 迭代规范（不断迭代升级的流程基线）

每个迭代（Iteration）固定执行五步，缺一不可：

1. **规划**：读 `开发须知.md` 与相关 skill → 确认变更范围 → 更新 spec/tasks
2. **开发**：按 tasks.md 的 SubTask 粒度编码（每完成一个 SubTask 即 commit + push 到 Gitee）
3. **验证**：构建 `BUILD SUCCESSFUL` + Code Linter 无 ERROR + 相关测试通过
4. **体检**：AppAnalyzer 规则体检，修复性能/兼容性告警
5. **收尾**：更新 checklist.md 勾选状态 → 提交变更 → 推送

## 阶段十一：质量加固（Testing & Quality）

- Task 22: 单元测试补齐（Local Test，`src/test/`）
  - 22.1: 金额计算测试：商品总价、配送费、优惠券抵扣、实付金额
  - 22.2: 订单状态流转测试：待付款→待接单→制作中→配送中→已完成，含取消/退款分支
  - 22.3: `normalizeData` 归一化测试：脏数据（缺字段/非对象/空数组）不崩溃并回退默认值
  - 22.4: 数据完整性测试：MockDataService 各集合（店铺/商品/订单/优惠券）数量、字段非空、ID 唯一
  - 22.5: 登录校验测试：正确/错误账号密码、角色判断、注册重名校验
- Task 23: 静态检查与告警清理
  - 23.1: 运行 Code Linter，清理 ERROR 级别问题
  - 23.2: 记录并处理 WARN 级别（deprecated API 替换等）

## 阶段十二：上架准备（Release Ready）

- Task 24: 上架材料与配置
  - 24.1: 完善 `AppScope/app.json5` 版本信息（versionName 1.0.0、vendor 等）
  - 24.2: 确认/调整 bundleName 与 AGC 应用包名一致
  - 24.3: 权限收敛：核对 `module.json5` 权限必要性（定位权限 reason/usedScene 完整）
- Task 25: 隐私合规
  - 25.1: 新增隐私政策展示页（SettingsPage 增加入口，展示隐私政策全文）
  - 25.2: 首次启动隐私弹窗（同意后才继续，记录同意状态到 preferences）
  - 25.3: 准备可公网访问的隐私政策网页版（供 AGC 填写）
- Task 26: 发布签名与构建
  - 26.1: 按 `harmonyos-release-publish` 技能生成密钥、申请发布证书与 Profile
  - 26.2: 配置 Signing Configs（SHA256withECDSA）
  - 26.3: `Build APP(s)` 构建带签名 Release 包，安装到真机冒烟验证
- Task 27: 上架自检
  - 27.1: AppAnalyzer 上架前体检，修复阻塞项
  - 27.2: 按发布技能 Checklist 逐项确认（软著/备案/隐私政策/截图/图标）

## 阶段十三：性能优化落地（Performance）

- Task 28: 长列表懒加载改造
  - 28.1: 首页店铺列表：ForEach → LazyForEach + IDataSource + cachedCount
  - 28.2: 订单列表、搜索结果、优惠券列表、评价列表同规格改造
  - 28.3: 列表项组件加 `@Reusable`，`aboutToReuse` 重置状态
- Task 29: 状态与动画优化
  - 29.1: 状态拆分：局部状态不下沉到 AppStorage，避免放大重绘
  - 29.2: 动画检查：无逐帧 @State 驱动的多余动画，统一 animateTo/transition
  - 29.3: Profiler 抽测关键页面帧率（首页滚动、订单列表）

## 阶段十四：体验与细节打磨（Polish）

- Task 30: 交互细节
  - 30.1: 全局空态/加载态/错误提示统一（EmptyState、LoadingIndicator）
  - 30.2: 返回键/手势行为检查（子页面返回不丢状态）
  - 30.3: 深色模式适配检查（dark/element/color.json 对照）
- Task 31: 数据健壮性
  - 31.1: 持久化数据版本迁移机制（version 字段 + 迁移函数）
  - 31.2: 极端数据模拟验证（订单 items 为空、余额不足、优惠券过期）

## 阶段十五：真实后端数据链路（Backend & Sync）

> 前置背景：客户端当前为单机 Mock 架构（每台设备数据独立，无法多设备协作）。本阶段引入 `server/` 轻量后端（Spring Boot 3.5 + Java 25 + SQLite），实现多用户真实买卖闭环。

### 后端已完成（server/ 目录，2026-08 已交付）

- **技术栈**：Spring Boot 3.5.4 / Java 25 / SQLite（免安装）/ JWT 认证 / JdbcTemplate
- **已实现接口**：
  - 认证：注册、登录（JWT）、个人信息
  - 店铺/商品：分类、店铺列表/详情、商品列表、商户建店/改店/增删改商品
  - 订单：用户下单（余额扣减+优惠券抵扣）、订单列表/详情、取消/确认收货、商户接单→出餐→完成流转、评价
  - 用户中心：优惠券领取/列表、收藏切换/列表、地址增删/设默认、店铺评价浏览、搜索
  - 商户统计：今日/本周/月订单数与收入
- **种子数据**：8 分类 / 30 店铺 / 每店 30 商品 / 5 测试账号（密码 123456，与客户端一致）
- **冒烟验证**：用户下单→商户接单→出餐→完成→统计 全链路通过

### 后续任务（后端方向）

- Task 32: 客户端接入真实后端（关键）
  - 32.1: `HttpClient.ets` 的 `USE_MOCK` 改为 false，`API_CONFIG.BASE_URL` 指向服务器地址
  - 32.2: `AppStorageManager.ets` 登录/注册改调服务端接口，token 持久化
  - 32.3: 首页店铺/商品改从服务端拉取（首次启动缓存）
  - 32.4: 下单/订单列表/状态流转全部走 API，移除本地订单生成
  - 32.5: 商户端订单/统计/店铺管理走 API
  - 32.6: 地址/优惠券/收藏/评价走 API
- Task 33: 实时同步
  - 33.1: 商户新订单轮询（或 WebSocket）提醒
  - 33.2: 用户订单状态变更拉取刷新
  - 33.3: 配送进度模拟改由服务端驱动（订单状态时间字段）
- Task 34: 部署与安全
  - 34.1: 后端部署到云服务器/局域网主机，防火墙开放 8080
  - 34.2: JWT 密钥改环境变量注入，密码哈希升级 BCrypt（可选）
  - 34.3: 局域网联调：模拟器/真机访问后端地址（真机需同网段 IP）

### 客户端改造注意（防坑）

- 客户端 `Models.ets` 与后端 JSON 字段一一对应（驼峰命名），后端已按客户端结构输出（tags/categoryIds/items/address 均为结构体）
- 登录响应为 `{token, user}`，客户端需保存 token 并在每次请求带 `Authorization: Bearer <token>`
- 游客可浏览店铺/商品/分类/评价/搜索；下单、商户操作等需登录
- 订单状态码两端一致：0待付款 1待接单 2制作中 3配送中 4已完成 5已取消 6退款中

## Impact
- Affected specs: `complete-takeout-app`、`fix-routing-and-persistence`（在其之上继续迭代）
- Affected code:
  - `entry/src/test/*.ets`（新增 Order.test、Coupon.test、DataPersistence.test 等）
  - `AppScope/app.json5`（版本信息）
  - `entry/src/main/module.json5`（权限核对）
  - `entry/src/main/pages/SettingsPage.ets`（隐私政策入口）
  - 新增隐私政策页面与启动隐私弹窗逻辑
  - 长列表页面（LazyForEach 改造）
  - `build-profile.json5`（签名配置，本地不提交密钥）
- 新增文档类产物：隐私政策文本（页面内嵌 + 网页版）

## ADDED Requirements

### Requirement: 单元测试覆盖
系统 SHALL 为金额计算、订单状态流转、数据归一化、Mock 数据完整性、登录校验提供单元测试，测试 SHALL 位于 `src/test/` 且无需设备可运行。

#### Scenario: 金额计算正确
- **WHEN** 单元测试执行
- **THEN** 商品总价+配送费-优惠金额=实付金额，边界（无优惠券/满减门槛）断言通过

#### Scenario: 脏数据不崩溃
- **WHEN** 持久化数据损坏（缺字段/非对象/空数组）时执行 normalizeData
- **THEN** 返回兜底默认值，不抛异常

### Requirement: 隐私合规
系统 SHALL 在首次启动时展示隐私政策弹窗，用户同意后才进入主流程；设置页 SHALL 提供隐私政策查看入口。

#### Scenario: 首次启动隐私弹窗
- **WHEN** 用户首次启动 App
- **THEN** 展示隐私政策弹窗，点击"同意"后进入首页并记录同意状态

### Requirement: 发布签名与构建
工程 SHALL 配置发布签名（发布证书 .cer + Profile .p7b），可构建带签名的 Release APP 包并安装到真机运行。

#### Scenario: 构建发布包
- **WHEN** 执行 Build APP(s)
- **THEN** 产物为带发布签名的 .app 文件，可安装到真机

### Requirement: 长列表性能
店铺/订单/搜索/优惠券/评价列表 SHALL 使用 LazyForEach + IDataSource，列表项组件使用 @Reusable。

#### Scenario: 大数据量滚动流畅
- **WHEN** 列表数据达数百条时滚动
- **THEN** 帧率稳定（≥50fps），内存无明显增长

## MODIFIED Requirements

### Requirement: 版本号管理
`AppScope/app.json5` 的 versionCode/versionName SHALL 在每次发布前递增，versionCode 规则：主版本×1000000 + 次版本×1000 + 修订版本。

## REMOVED Requirements
无
