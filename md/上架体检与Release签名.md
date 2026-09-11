# Release 签名与上架体检

> 本文对应「未完成项」第 5 条：Release 签名 / 上架体检。目标是让「打包 → 签名 → 体检 → 上架」在仓库内有可复现的落地路径，
> 并明确区分「仓库内可自动完成的项」与「必须由开发者在华为开发者账号下人工完成的外部资源项」。

## 一、当前状态（一句话结论）

| 环节 | 状态 | 说明 |
| --- | --- | --- |
| Release 编译 | ✅ 可复现 | `scripts/build-release.ps1 -AllowUnsigned` 可产出 Release 编译产物 |
| Release 签名 | ⏳ 待外部证书 | `build-profile.json5` 的 `signingConfigs` 为空，未产出签名包；证书需在 AGC 申请 |
| 上架体检 | ✅ 可复现（静态） | `scripts/release-check.ps1` 输出 `md/上架体检报告.md` |
| IDE 体检 | ⏳ 需在 IDE 内执行 | Code Linter（Code → Inspect Code）与 AppAnalyzer（Tools → AppAnalyzer）无可用命令行入口 |
| HTTPS / 正式域名 | ⏳ 待外部资源 | `API_CONFIG.USE_HTTPS=false`、`RELEASE_BASE_URL` 仍为示例域名 |

**未完成的原因不是代码缺失，而是缺少外部资源**：发布证书（.p12/.cer/.p7b）只能在开发者账号下申请，
正式 HTTPS 域名需备案。因此本仓库交付的是「一条命令即可接入」的工具链 + 可复现体检报告，证书到位后无需改代码。

## 二、Release 签名接入（3 步）

### 1. 申请签名材料（华为开发者账号，人工）

1. DevEco Studio → **Build → Generate Key and CSR**：新建 `.p12` 密钥库（别名如 `takeout_release_2026`，有效期建议 25 年），同时产出 `.csr`。
2. [AppGallery Connect](https://developer.huawei.com/consumer/cn/appgallery-connect) → **证书、App ID 和 Profile → 数字证书** → 新增 → 类型选**发布证书** → 上传 `.csr` → 下载 `.cer`。
3. 同页 → **Profile** → 添加 → 类型选**发布** → 关联上一步证书与包名 `com.example.jiandanwaimai` → 下载 `.p7b`。

> 包名必须与 `AppScope/app.json5` 的 `bundleName` 完全一致；上架前建议把 `com.example.*` 改为自有域名反写。

### 2. 一条命令接入工程

```powershell
powershell -ExecutionPolicy Bypass -File scripts/enable-release-signing.ps1 `
  -StoreFile D:\secure\takeout-release.p12 -StorePassword '你的密钥库密码' `
  -KeyAlias takeout_release_2026 -KeyPassword '你的密钥密码' `
  -ProfileFile D:\secure\takeout-release.p7b -CertFile D:\secure\takeout-release.cer
```

脚本行为：

- 校验三个材料文件是否存在，缺一即报错退出（不会写出半成品配置）；
- 生成 `signing/release-signing.json5`（含密码，已在 `.gitignore` 中排除）；
- 幂等写入 `build-profile.json5` 的 `signingConfigs`（`name: default`，与 `products[].signingConfig` 对应）；
- 需要还原时执行 `scripts/enable-release-signing.ps1 -Revert`，恢复 `"signingConfigs": []` 并删除本地密码文件。

**密码不会进入 Git**：`.gitignore` 已忽略 `signing/**/*.p12|cer|p7b|csr` 与 `signing/release-signing.json5`。
请注意 `build-profile.json5` 本身是被跟踪的文件，签名接入后如误提交会泄露密码，提交前请确认 `git status` 中它的改动已还原。

### 3. 产出签名包

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-release.ps1        # 签名 HAP
powershell -ExecutionPolicy Bypass -File scripts/build-release.ps1 -App   # 上架用 APP 包
```

未接入签名时会直接失败并给出接入指引（避免把 unsigned 包误当成上架包）；
产物校验会明确列出 `*-signed.hap` / `*-signed.app` 与 `*unsigned.hap`。

## 三、上架体检

```powershell
powershell -ExecutionPolicy Bypass -File scripts/release-check.ps1          # 静态体检
powershell -ExecutionPolicy Bypass -File scripts/release-check.ps1 -Build   # 体检 + Release 构建
```

退出码 = FAIL 项数量（0 表示无阻塞项），同时输出 `md/上架体检报告.md`。覆盖：

- 应用信息：包名 / versionCode / versionName / 图标 / 名称 / vendor；
- 权限与隐私：敏感权限是否带 `reason` 与 `usedScene`（上架审核关注点）；
- 页面注册：`pages/**` 中所有 `@Entry` 页面是否都在 `main_pages.json` 中，路由表是否存在失效条目；
- 网络与安全：`USE_HTTPS` 开关、发布域名、高德 Key、后端 HTTPS 配置；
- 签名就绪：`signingConfigs` 与证书材料是否齐备；
- 产物：HAP/APP 是否存在、是否已签名；
- 人工项：隐私政策网址、软件著作权、APP 备案、应用截图、IDE 体检。

### 当前体检结果（示例）

```
PASS 页面注册：共 37 个 @Entry 页面均已注册（路由表 37 项）
FAIL HTTPS 开关：API_CONFIG.USE_HTTPS 仍为 false，发布包必须使用 HTTPS 域名
FAIL 发布域名：RELEASE_BASE_URL 仍为示例域名 https://api.example.com，需替换为真实备案域名
FAIL 签名配置：未配置发布证书（signing/ 下缺少 .p12/.cer/.p7b），当前只能产出 unsigned 包
WARN bundleName 含 example，上架前建议改为自有域名反写
```

### 关于 Code Linter / AppAnalyzer

DevEco Studio 的 Code Linter 与 AppAnalyzer 目前只有 IDE 入口：

- Code Linter：`Code → Inspect Code`（项目规则见根目录 `code-linter.json5`，历史结果在 `.appanalyzer/codelinter.json`，当前为 0 ERROR）；
- AppAnalyzer：`Tools → AppAnalyzer → 上架前体检`。

命令行插件 `plugins/codelinter/index.js` 在脱离 IDE 运行时会对工程内 `code-linter.json5` 报
“configuration file is in use” 而中止，因此**上架前仍建议在 IDE 内各跑一次**，本篇提供的脚本作为可复现的补充门禁。

## 四、上架前人工清单

| 项 | 说明 |
| --- | --- |
| 隐私政策网址 | AGC 必填，需公网可访问（项目内 `PrivacyPolicyPage` 为 App 内页面，需另行部署网页版） |
| 软件著作权 | AGC 版权信息需软著证书或代理证书 |
| APP 备案 | 工信部 APP 备案，未备案不能上架，建议尽早启动 |
| 应用材料 | 各分辨率截图、应用简介、分类、图标 |
| 正式域名与证书 | 后端部署 HTTPS，前端切换 `USE_HTTPS=true` 并替换 `RELEASE_BASE_URL` |
| 测试账号 | 审核说明中提供四端账号（用户/商户/管理/骑手，密码均 123456） |

## 五、相关文件

| 文件 | 作用 |
| --- | --- |
| `scripts/enable-release-signing.ps1` | 接入 / 还原发布签名配置 |
| `scripts/build-release.ps1` | Release 构建 + 签名产物校验 |
| `scripts/release-check.ps1` | 上架体检（可附 Release 构建） |
| `signing/release-signing.template.json5` | 签名材料字段说明模板 |
| `md/上架体检报告.md` | 体检报告输出（每次执行覆盖） |
