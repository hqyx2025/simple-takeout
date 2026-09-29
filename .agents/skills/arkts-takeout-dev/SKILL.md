---
name: arkts-takeout-dev
description: 开发简单外卖的 HarmonyOS API 26 ArkTS 页面，处理编译错误、路由、状态与持久化。
---

# ArkTS 实现与验证

按用户需求直接修改相关代码，完成后运行 debug HAP 构建。执行约定和构建命令见根目录 AGENTS.md；无需建立计划、任务清单、阶段审批或自动提交推送。

- 业务数据来自现有 service/API；四端角色为 CUSTOMER、MERCHANT、RIDER、ADMIN。路由使用 UiNavigation.routerCompat。
- 全站视觉以登录页为准，复用 AppTheme、Constants 和 PageHeader；图标/插图直接绘制本地 SVG，支持深浅色。
- 页面主体使用 Scroll/List + layoutWeight(1)，底部操作栏独立；表单有标签与占位示例，按钮有反馈。
- ArkTS 无 any/unknown，复杂字面量声明类型；Stack 用 alignContent，Row.alignItems 用 VerticalAlign。
- @CustomDialog 必须声明 controller；可选属性用 ??；渲染列表用显式 @State 数组，不用 getter。
- ForEach 项若被回调捕获，提取 @Builder 传参；列表更新检查对象替换与 key 是否触发重绘。
- 持久化数组先 Array.isArray 校验，保留合法地址；登出清账号缓存，登录从服务端恢复。
- UI 改动保留文案、测试 ID、业务校验与接口；不把支付、退款等业务含义当成纯样式修改。

涉及业务状态、隐私同意、地图或设备用例时，查阅 `md/开发参考.md` 对应主题。构建结果以 BUILD SUCCESSFUL 和 HAP 产物为准；设备未实测时明确说明。
