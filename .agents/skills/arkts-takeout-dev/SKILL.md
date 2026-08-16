---
name: arkts-takeout-dev
description: 鸿蒙HarmonyOS NEXT外卖App(简单外卖)开发技能,包含ArkTS编译错误修复、布局组件规范、持久化数据归一化、Canvas图表、状态管理与路由联动经验。当在本项目中开发新功能、修复编译/运行崩溃、添加页面或图表、或处理AppStorage/持久化数据时使用。
---

# ArkTS 外卖App开发

## 项目概况

- 项目:简单外卖(jiandanwaimai),HarmonyOS NEXT 毕设,Stage模型
- SDK:6.1.1(24)/ API 24;语言:ArkTS(严格类型,无 any/unknown)
- 数据:Mock 驱动,`MockDataService` 唯一数据源,`AppStorage` 状态管理 + `preferences` 持久化
- 路由:`@ohos.router`(pushUrl/back),页面必须加 `@Entry`

## 技能体系（开发时按需调用）

| 技能 | 适用场景 |
|---|---|
| [harmonyos-testing](../harmonyos-testing/SKILL.md) | 编写单元测试、静态检查、上架前体检 |
| [arkts-performance-optimization](../arkts-performance-optimization/SKILL.md) | 列表卡顿、LazyForEach 改造、状态拆分、动画优化 |
| [harmonyos-release-publish](../harmonyos-release-publish/SKILL.md) | 签名配置、打包、AGC 上架、审核材料 |
| [production-ready spec](../specs/production-ready/spec.md) | 可实装迭代规划（测试/上架/性能/打磨） |

## 迭代规范（不断迭代升级的流程基线）

每个迭代固定五步：**规划 → 开发 → 验证 → 体检 → 收尾**

1. **规划**：读 `开发须知.md` 与相关 skill → 确认变更范围 → 更新 spec/tasks
2. **开发**：按 tasks.md 的 SubTask 粒度编码（每完成一个 SubTask 即 commit + push 到 Gitee）
3. **验证**：构建 `BUILD SUCCESSFUL` + Code Linter 无 ERROR + 相关测试通过
4. **体检**：AppAnalyzer 规则体检，修复性能/兼容性告警
5. **收尾**：更新 checklist.md 勾选状态 → 提交变更 → 推送

> 长期目标：通过 production-ready spec 的阶段十一至十四（测试/上架/性能/打磨），最终产出可安装、可上架 AppGallery 的实装软件。

## 构建与验证

```bash
# 构建(必须验证通过才算完成)
& "C:\Software\Application\Devcostudio\DevEco Studio\tools\node\node.exe" "C:\Software\Application\Devcostudio\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
# 构建日志: .hvigor/outputs/build-logs/build.log (搜索 ERROR / BUILD SUCCESSFUL)
```

## 核心开发规范(违反即编译错误)

1. **禁止无类型对象字面量**:`{key: value}` 必须用 class + static create() 或 interface
2. **禁止硬编码**:颜色/间距/字号/圆角一律用 `Constants.ets` 的 COLORS/SPACING/FONT_SIZE/BORDER_RADIUS
3. **数据必须来自 service 层**:页面禁止硬编码新数据
4. **`main_pages.json` 只用 `src` 属性**,禁止 routerMap
5. **`@Builder` 参数**:无默认值,类型显式声明
6. **跨页共享数据**:AppStorage + `@StorageLink`/`@StorageProp`
7. **Git 规范**:每完成一个 SubTask 即 commit + push(`<type>(<scope>): <描述>`)

## 常见编译错误速查

| 错误 | 原因 | 修复 |
|---|---|---|
| `Property 'justifyContent' does not exist on type 'StackAttribute'` | Stack 不支持 justifyContent/alignItems | 改用 `.alignContent(Alignment.Center)` |
| `Property 'Top' does not exist on type 'typeof HorizontalAlign'` | Row 的 alignItems 用错枚举 | Row 用 `VerticalAlign.Top/Center/Bottom`;HorizontalAlign 只有 Start/Center/End |
| `Property 'CenterStart' does not exist on type 'typeof Alignment'` | Alignment 无 CenterStart | 用 `Alignment.Start`(垂直居中+水平起始) |
| `Property 'stateEffect' does not exist on type 'ColumnAttribute'` | API24 中 stateEffect 不支持 Column/Row/Text | 移除;仅 Button 等特定组件可用 |
| `'xxx' is possibly 'undefined'` | 可选字段未判空 | `(o.xxx ?? '')` 或 `o.xxx !== undefined` 守卫 |
| `Argument of type 'string \| Resource' is not assignable to 'string'` | Length 类型(宽高/Area.width) | `typeof w === 'number' ? w : Number.parseFloat(w)` 分型处理 |
| `arkts-no-untyped-obj-literals` | 裸对象字面量 | class + static create() |

## 持久化数据归一化(防启动崩溃)

`DataPersistence.loadAllData()` 恢复旧版本数据时,**必须做字段校验**,否则渲染 `ForEach(order.items)` 等位置会 `Cannot read property length of undefined` 崩溃:

- `user`:补齐 `coupons/orders/storeIds/balance` 等字段,非对象回退 `getDefaultUser()`
- `orderList`:丢弃无 `id` 的脏数据,`items` 缺失兜底 `[]`,`address` 异常用默认地址
- 数组类(cartItems/favoriteList/couponList/addressList):`Array.isArray` 校验,损坏回退默认值

模式见 `entry/src/main/ets/service/DataPersistence.ets` 的 `normalizeData`。

## 启动流程(勿乱改)

```
EntryAbility.onCreate
  ├─ AppStorage.setOrCreate('appContext', this.context)
  └─ loadAllData() 异步恢复持久化数据(归一化后 setOrCreate)
Index.aboutToAppear
  └─ initAppStorage() 若 _persistenceReady 未置位则初始化默认值
```

## 页面路由与 Tab 联动

- 独立页面(`pages/XxxPage`)必须 `@Entry` + `main_pages.json` 注册
- 首页 4 Tab 在 `Index.ets`;店铺详情在"发现"Tab(DiscoverPage),通过 `AppStorage('selectedStoreId')` 驱动
- 从子页面返回展示店铺:`AppStorage.setOrCreate('currentStoreId', id)` + `router.back()`,Index 的 `onPageShow` 读取并切 Tab(见 Index.showStoreDetail)
- 回调传参:`router.pushUrl` 页面无法注入回调,onBack/onClick 默认实现直接 `router.back()`

## Canvas 图表模式

商户统计图(近7天折线/状态柱状)模式:
- 每个 Canvas 独立 `CanvasRenderingContext2D(new RenderingContextSettings(true))`
- `.onReady(() => this.drawXxx())` 中绘制,用 `ctx.width/ctx.height` 自适应
- 数据方法放 service 层(`AppStorageManager.getMerchantWeekRevenue` 等),页面只负责绘制
- 最小值兜底(除零保护):`if (max <= 0) max = 1`

## 动画模式

- 循环动画:`setInterval` 驱动 `@State` 进度 + `.animation({duration, curve: Curve.Linear})`
- 生命周期:`aboutToAppear` 启动,`aboutToDisappear` 清理(`clearInterval`)
- 骑手配送动画见 OrderDetailPage.RiderTracking(进度条 + translate 移动图标)

## 详细参考

- 布局与组件规范细节:[reference.md](reference.md)
- 测试账号(密码均 123456):用户 13800138000/13900139000;商户 13600136000/13700137000/13500135000
- 订单状态码:0待付款 1待接单 2制作中 3配送中 4已完成 5已取消 6退款中

