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
6. **提交审核**：审核周期通常 3-7 …13781 tokens truncated…ts 中用 preferences 持久化 isLoggedIn、user、cartItems、orderList、favoriteList、addressList、couponList
  - [x] SubTask 25.2: 在 EntryAbility.ets onCreate 中调用持久化数据初始化
  - [x] SubTask 25.3: 验证 App 重启后数据保留

## 阶段七：集成补全与体验打磨
- [x] Task 26: 首页发现 Tab 店铺详情返回处理
  - [x] SubTask 26.1: 从收藏页/搜索页点击店铺后，正确切换到发现 Tab 展示店铺详情（Index.ets onPageShow 监听 currentStoreId；SearchPage 返回/店铺点击改为 router 实现）

## 阶段八：商户端图表统计
- [x] Task 27: 商户收入统计图表
  - [x] SubTask 27.1: 在 MerchantStatsPage 增加 Canvas 绘制的近7天收入趋势折线图
  - [x] SubTask 27.2: 增加今日订单状态分布柱状图（AppStorageManager 新增 getMerchantWeekRevenue/getMerchantTodayStatusOrders）

## 阶段九：配送跟踪可视化
- [x] Task 28: 订单配送跟踪动画
  - [x] SubTask 28.1: 订单详情页配送中状态增加骑手位置动画（RiderTracking 组件，骑手图标沿轨道移动）
  - [x] SubTask 28.2: 配送预估时间展示

## 阶段十：UI 细节打磨
- [x] Task 29: UI 体验优化
  - [x] SubTask 29.1: 创建 LoadingIndicator 组件，统一加载态（已接入结算页模拟支付）
  - [x] SubTask 29.2: 首页店铺卡片视觉优化（评分星星改用 RatingStars 组件、标签圆角样式）
  - [x] SubTask 29.3: 按钮交互反馈优化（购物车栏禁用态、结算按钮 enabled 控制）

# Task Dependencies
- Task 23 依赖 Task 22（OrderDetailPage 需先有 @Entry）
- Task 24 依赖 Task 22（CheckoutPage 需先有 @Entry）
- Task 25 独立，可与 Task 22-24 并行
- Task 26 依赖 Task 22
- Task 27-29 依赖 Task 22-26 完成（先修复阻塞性问题再做增强）

