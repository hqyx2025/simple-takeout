# 脚本说明

| 脚本 | 用途 | 前置条件 / 产物 |
| --- | --- | --- |
| `device-uitest.ps1`、`device-test.ps1` | 构建、安装并运行设备 UiTest | DevEco Studio、hdc、已连接设备；日志写入 `TemporaryCacheStorage/` |
| `device-checkout-regression.ps1`、`device-merchant-regression.ps1`、`device-review-regression.ps1`、`device-role-regression.ps1`、`rider-chain-regression.ps1` | 四端设备链路回归 | 已启动后端和设备；截图/日志写入 `TemporaryCacheStorage/` |
| `build-release.ps1`、`enable-release-signing.ps1`、`release-check.ps1` | Release 构建与签名检查 | `DEVECO_HOME` 或默认 DevEco 安装目录；报告为生成物 |
| `acceptance-performance.py` | 只读 API 性能验收 | Python 3 标准库；`TAKEOUT_PERF_TOKEN`；报告写入 `TemporaryCacheStorage/performance/` |
| `*.test.cjs`、`check-*.cjs` | ArkTS / Web 回归与静态检查 | Node.js；部分脚本需要 DevEco TypeScript，使用 `DEVECO_HOME` / `DEVECO_SDK_HOME`；不等同设备测试 |
| `export-database.ps1`、`start-alipay-sandbox.ps1` | 数据导出与沙箱辅助 | 本机 MySQL / 支付宝沙箱配置 |
| `web-browse.test.cjs` | 网页四端浏览、结算恢复、退款闭环、骑手履约与账号 / 异步隔离回归 | Node.js 原生测试；2026-10-25 的 6 项为历史基线，后续已随六批 UX 扩展 |
| `web-location.test.cjs`、`web-urls.test.cjs` | 定位失败反馈、手选地点坐标和根路径 / `/takeout/` API、上传资源路径回归 | Node.js 原生测试；不请求真实定位授权，不代表物理真机 GPS 验收 |
| `checkout-coupon-session.test.cjs` | 执行真实 ArkTS 规则 / 非渲染方法，验证券资格、结算草稿、冻结请求与终态重放 | Node.js + DevEco TypeScript；不等同 ArkUI 渲染或 Hypium 已运行 |
| `cart-flight.test.cjs`、`store-cart-rapid-click.test.cjs` | 购物车异步隔离与快速连续操作回归 | Node.js + DevEco TypeScript；设备行为需另外实测 |
| `recover-login-account.py` | 既有 root SSH 通道下核验或恢复一个启用管理员的登录预算 | 默认只读；`--apply` 清目标账号预算并重启全部 app，会丢失全部本地窗口并中断在途请求，不能当作无中断解锁 |
| `seed-demo-catalog.py` | 生成并校验 500 店、6000 菜品目录；支持预检、备份后增量导入 | Python 3；`self-test` 不写业务库，`apply` 会写库；2026-10-25 安全复测基线为线上 540 店，当时终轮发布没有重新播种 |
| `catalog-photos.py` | 下载带来源记录的目录图片，替换已知演示占位图 | 图片文件先复制到目标上传卷；`apply` 会更新数据库，不能与只读验证混淆 |

脚本默认从 `DEVECO_HOME` 读取 DevEco Studio 根目录；未设置时使用 `C:\Program Files\Huawei\DevEco Studio`。源码和 PowerShell 脚本按 UTF-8 读写，临时文件不要写入仓库根目录。

2026-10-25 安全复测基线版本为 `defense-20261025-225329`。[终轮报告](../md/audit/round10/第十轮防御-回复.md) 对应的临时执行脚本与原始输出保存在 `TemporaryCacheStorage/round10-defense/`，文档原稿和更新证据在 `TemporaryCacheStorage/docs-current-sync/`；用户要求留存，不清理这些证据。历史线上验收脚本会创建 QA 账号，不能当作只读探活重复执行。

六批业务与交互改造已于 2026-10-26 19:57:59 +0800 随 `ux-20261026-1950-sync` 发布到体验站，发布源提交 `e6190a9`；实际改动和限制见 [诊断与实施记录](../md/人性化改造诊断与实施方案.md)。HTTPS 首页与 4 个静态资源哈希匹配构建，管理员只读接口与服务健康核验通过；线上未启用其他角色作测试，也未运行线上交易链。GitHub Actions 尚未全部通过，不能把服务器上线当作工作流全绿。正式支付、物理真机、Release 签名、完整证据工单与结算后售后政策仍需专项完成。

从仓库根目录执行 Web 与结算规则回归：

```powershell
node --test scripts/web-browse.test.cjs scripts/web-location.test.cjs scripts/web-urls.test.cjs scripts/checkout-coupon-session.test.cjs
node --check server/takeout-gateway/src/main/resources/static/app.js
node --check server/takeout-gateway/src/main/resources/static/location.js
node --check server/takeout-gateway/src/main/resources/static/urls.js
```

本次发版前上述四套回归 76 / 76 通过，三个静态脚本语法检查通过；debug HAP 为 `BUILD SUCCESSFUL`，API 顺序为正式域名优先、本地回退，产物未签名，已保存在服务器 release 的 `artifacts/mobile/`，没有公开下载或 AppGallery 发布。Maven 应用模块 646 项（61 项条件跳过）和网关 9 项零失败，独立真实 MySQL 回归 36 项、0 跳过。前端日志为 `TemporaryCacheStorage/publish-web-tests.log` 和 `publish-hap-build.log`；本地模拟器链路与线上只读核验须分开，不以 Node 通过推断全端线上验收完成。
