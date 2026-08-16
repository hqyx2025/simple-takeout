---
name: harmonyos-release-publish
description: 鸿蒙HarmonyOS NEXT应用发布上架技能，覆盖发布证书/Profile申请、签名配置、Release构建APP包、AppGallery Connect上架全流程与审核要点。当项目需要打包签名、构建可安装包、准备上架材料或处理上架审核问题时使用。
---

# HarmonyOS 应用发布上架

## 核心概念（不可混淆）

| 文件 | 后缀 | 作用 | 获取方式 |
|---|---|---|---|
| 密钥库 | `.p12` | 私钥，本地生成 | DevEco Studio: Build → Generate Key and CSR |
| 证书请求文件 | `.csr` | 申请证书用 | 同上（生成密钥时一并产出） |
| 发布证书 | `.cer` | 身份证书 | AppGallery Connect 上传 `.csr` 签发下载 |
| Profile 文件 | `.p7b` | 授权清单（含包名/证书绑定） | AGC 关联证书后生成下载 |

> 关键事实：**没有签名的包无法安装真机，更无法上架**。调试证书仅限开发调试，上架必须用发布证书 + 发布 Profile。

## 一、签名配置流程（手动签名）

### 1. 生成密钥和证书请求文件
1. DevEco Studio 菜单：**Build → Generate Key and CSR**
2. Key Store File：点 New 创建 `.p12` 密钥库（密码 ≥8 位，含大小写+数字+符号两种以上）
3. Alias 命名规范：`myapp_release_2026` 之类有意义的名字
4. Validity：建议 25 年以上
5. Certificate：填写组织信息（姓名/组织/城市/国家码），保存 `.csr` 路径

### 2. 申请发布证书与 Profile
1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/appgallery-connect)
2. 左侧导航 → **数字证书** → 新增 → 类型选**发布证书** → 上传 `.csr` → 下载 `.cer`
3. 左侧导航 → **Profile** → 添加 → 类型选**发布** → 关联上一步证书 → 下载 `.p7b`

### 3. 配置工程签名信息
DevEco Studio：**File → Project Structure → Project → Signing Configs**，取消 "Automatically generate signature"，手动填写：

| 字段 | 值 |
|---|---|
| Store File | `.p12` 密钥库文件 |
| Store Password | 生成密钥时的密码 |
| Key Alias | 生成的别名 |
| Key Password | 与 Store Password 一致 |
| Sign Alg | `SHA256withECDSA`（固定值，不可改） |
| Profile File | `.p7b` 文件 |
| Certpath File | `.cer` 文件 |

### 4. 构建发布包
1. 菜单：**Build → Build Hap(s)/APP(s) → Build APP(s)**（构建模式 `<Default>` 时 APP 包默认 Release）
2. 产物路径：工程目录 `build/outputs/{product}/` 下，取**带签名**的 `.app` 文件
3. 注意：打包 APP 时会把所有 HAP/HSP 模块打包进去，有多余模块先删除
4. HAP 大小限制：按声明设备类型有上限（手机 4GB 内），APP 包 ≤4GB

## 二、AGC 上架流程

1. **创建应用**：AGC → 我的应用 → HarmonyOS 页签 → 添加应用（包名须与工程 `bundleName` 一致，且未被占用）
2. **完善应用信息**：应用名称（须与软著证书名称一致）、图标、分类、截图、描述、**隐私政策网址**（必须可公网访问）
3. **上传软件包**：上传带发布签名的 `.app` 包
4. **配置版权信息**：上传软件著作权登记证书（或代理证书）
5. **填写备案信息**：APP 备案（工信部要求，未备案不能上架，建议开发早期就启动）
6. **提交审核**：审核周期通常 3-7 天，重点查隐私合规与功能稳定性

## 三、上架前置材料清单

| 材料 | 说明 | 建议启动时机 |
|---|---|---|
| 软件著作权证书 | 上架必备，软件名称须与应用名一致 | 开发初期（周期长） |
| APP 备案 | 工信部要求，未备案不得上架 | 注册应用后立刻开始 |
| 隐私政策网址 | 可公网访问的网页，声明收集哪些信息 | 上架前 2 周 |
| 隐私标签 | 应用详情页展示如何使用个人数据 | 上架前 |
| 发布证书 + Profile | `.cer` + `.p7b` | 功能冻结后 |

## 四、审核常见驳回原因（提前自检）

1. **个人信息保护不合规**：隐私政策内容不完整、权限申请无理由或超范围
2. **功能异常**：崩溃、闪退、核心流程不可用
3. **权限滥用**：非必要权限（本项目的定位权限要写清楚 `reason` 与 `usedScene`）
4. **包名/名称不一致**：应用名与软著证书不一致、bundleName 与创建应用时不一致
5. 提交前用 **上架前体检**（Tools → AppAnalyzer）提前检测上架阻塞问题

## 五、本项目的上架差异点

- bundleName 为 `com.example.jiandanwaimai`，上架前需在 AGC 创建同名应用；若该包名被占用需先改 bundleName（AppScope/app.json5 + entry module.json5 同步）
- 版本号管理：`AppScope/app.json5` 的 `versionCode`（1000000 = 1.0.0，递增规则）与 `versionName`
- 权限收敛：当前申请了 `LOCATION`（精确定位），如定位仅用于搜索选点可考虑只保留 `APPROXIMATELY_LOCATION`，减少审核阻力
- Mock 数据项目无真实后端，上架审核要求功能正常可演示，所有核心链路必须可完整跑通

## 六、发布前验收 Checklist

- [ ] Debug 全链路测试通过（登录→下单→商户接单→配送→完成→评价）
- [ ] Code Linter 静态检查无 ERROR 级别问题
- [ ] 上架前体检（AppAnalyzer）无阻塞项
- [ ] 隐私政策页面已部署可访问
- [ ] 应用图标/启动图符合规格（分层图标）
- [ ] 版本号已递增、buildVersion 已更新
- [ ] 发布证书 + Profile 已申请并配置
- [ ] `Build APP(s)` 产物带签名、可安装
